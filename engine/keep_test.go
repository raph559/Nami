package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/storage"
	"golang.org/x/time/rate"
)

// A local seeder for a pack of two files, and its .torrent served over HTTP.
type pack struct {
	seeder *torrent.Client
	url    string
	first  []byte
}

func newPack(t *testing.T) *pack {
	t.Helper()
	// Not t.TempDir: on Windows the seeder holds its files a little after closing.
	parent, err := os.MkdirTemp("", "nami-pack")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(parent) })
	root := filepath.Join(parent, "pack")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	var first []byte
	for i, name := range []string{"ep1.mkv", "ep2.mkv"} {
		data := make([]byte, 1<<20)
		rand.New(rand.NewSource(int64(i + 1))).Read(data)
		if i == 0 {
			first = data
		}
		if err := os.WriteFile(filepath.Join(root, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	info := metainfo.Info{PieceLength: 1 << 16}
	if err := info.BuildFromFilePath(root); err != nil {
		t.Fatal(err)
	}
	var mi metainfo.MetaInfo
	if mi.InfoBytes, err = bencode.Marshal(info); err != nil {
		t.Fatal(err)
	}
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = filepath.Dir(root)
	cfg.Seed = true
	cfg.ListenPort = 0
	cfg.NoDHT = true
	files := storage.NewFile(cfg.DataDir)
	cfg.DefaultStorage = files
	seeder, err := torrent.NewClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		seeder.Close()
		files.Close()
	})
	st, err := seeder.AddTorrent(&mi)
	if err != nil {
		t.Fatal(err)
	}
	<-st.GotInfo()
	if err := st.VerifyDataContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { _ = mi.Write(w) }))
	t.Cleanup(srv.Close)
	return &pack{seeder: seeder, url: srv.URL, first: first}
}

// Not t.TempDir: on Windows the engine holds its files a little after closing.
func keepDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "nami-keep")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

func newTestEngine(t *testing.T) (*engine, string) {
	t.Helper()
	e, err := newEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		e.client.Close()
		e.closeStorages()
	})
	return e, fmt.Sprintf("http://127.0.0.1:%d", e.port)
}

func post(t *testing.T, url string, body any) *http.Response {
	t.Helper()
	data, _ := json.Marshal(body)
	resp, err := http.Post(url, "application/json", bytes.NewReader(data))
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func add(t *testing.T, base, uri, dir string) addResult {
	t.Helper()
	resp := post(t, base+"/add", map[string]string{"uri": uri, "dir": dir})
	var res addResult
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil || resp.StatusCode != 200 {
		t.Fatalf("add: %d %v", resp.StatusCode, err)
	}
	return res
}

func keepStats(t *testing.T, base, hash string, index int) keepJSON {
	t.Helper()
	resp, err := http.Get(fmt.Sprintf("%s/keep/%s/%d", base, hash, index))
	if err != nil {
		t.Fatal(err)
	}
	var s keepJSON
	if err := json.NewDecoder(resp.Body).Decode(&s); err != nil {
		t.Fatal(err)
	}
	return s
}

func waitDone(t *testing.T, base, hash string, index int) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		if s := keepStats(t, base, hash, index); s.Total > 0 && s.Done == s.Total {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("file %d did not finish", index)
}

func startKeep(t *testing.T, e *engine, base string, p *pack, dir string, index int) string {
	t.Helper()
	res := add(t, base, p.url, dir)
	if r := post(t, fmt.Sprintf("%s/keep/%s/%d", base, res.Hash, index), nil); r.StatusCode != http.StatusNoContent {
		t.Fatalf("keep: %d", r.StatusCode)
	}
	tt, ok := e.lookup(res.Hash)
	if !ok {
		t.Fatal("torrent not in client")
	}
	tt.AddClientPeer(p.seeder)
	return res.Hash
}

func TestKeepFetchesOnlyThatFile(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	waitDone(t, base, hash, 0)
	if s := keepStats(t, base, hash, 1); s.Done == s.Total {
		t.Fatalf("the other file came too: %+v", s)
	}
}

func TestFinishMovesFile(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	waitDone(t, base, hash, 0)
	dest := filepath.Join(t.TempDir(), "sub", "1-1.mkv")
	if r := post(t, fmt.Sprintf("%s/finish/%s/0", base, hash), map[string]string{"dest": dest}); r.StatusCode != http.StatusNoContent {
		t.Fatalf("finish: %d", r.StatusCode)
	}
	got, err := os.ReadFile(dest)
	if err != nil || !bytes.Equal(got, p.first) {
		t.Fatalf("moved file differs: %v", err)
	}
}

func TestFinishRefusesPartialFile(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	_, base := newTestEngine(t)
	res := add(t, base, p.url, dir)
	post(t, fmt.Sprintf("%s/keep/%s/0", base, res.Hash), nil)
	r := post(t, fmt.Sprintf("%s/finish/%s/0", base, res.Hash), map[string]string{"dest": filepath.Join(t.TempDir(), "x")})
	if r.StatusCode != http.StatusConflict {
		t.Fatalf("finish: %d", r.StatusCode)
	}
}

func TestFinishLastRemovesPartial(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	waitDone(t, base, hash, 0)
	post(t, fmt.Sprintf("%s/finish/%s/0", base, hash), map[string]string{"dest": filepath.Join(t.TempDir(), "x")})
	if _, ok := e.lookup(hash); ok {
		t.Fatal("torrent still in client")
	}
	// Windows can hold a mapped file for long; the app sweeps it at the next launch.
	if _, err := os.Stat(filepath.Join(dir, hash)); !os.IsNotExist(err) && runtime.GOOS != "windows" {
		t.Fatalf("partial data left: %v", err)
	}
}

func TestPackFinishKeepsOther(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	post(t, fmt.Sprintf("%s/keep/%s/1", base, hash), nil)
	waitDone(t, base, hash, 0)
	waitDone(t, base, hash, 1)
	post(t, fmt.Sprintf("%s/finish/%s/0", base, hash), map[string]string{"dest": filepath.Join(t.TempDir(), "x")})
	if _, ok := e.lookup(hash); !ok {
		t.Fatal("torrent gone while a file is still kept")
	}
	dest := filepath.Join(t.TempDir(), "y")
	if r := post(t, fmt.Sprintf("%s/finish/%s/1", base, hash), map[string]string{"dest": dest}); r.StatusCode != http.StatusNoContent {
		t.Fatalf("finish second: %d", r.StatusCode)
	}
	if st, err := os.Stat(dest); err != nil || st.Size() != 1<<20 {
		t.Fatalf("second file: %v", err)
	}
}

func TestUnkeepReleases(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	if r := post(t, fmt.Sprintf("%s/unkeep/%s/0", base, hash), nil); r.StatusCode != http.StatusNoContent {
		t.Fatalf("unkeep: %d", r.StatusCode)
	}
	if _, ok := e.lookup(hash); ok {
		t.Fatal("torrent still in client")
	}
	if _, err := os.Stat(filepath.Join(dir, hash)); !os.IsNotExist(err) {
		t.Fatalf("partial data left: %v", err)
	}
	if r := post(t, fmt.Sprintf("%s/unkeep/%s/0", base, hash), nil); r.StatusCode != http.StatusNoContent {
		t.Fatalf("second unkeep: %d", r.StatusCode)
	}
}

func TestPauseStopsAndKeepResumes(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	res := add(t, base, p.url, dir)
	post(t, fmt.Sprintf("%s/keep/%s/0", base, res.Hash), nil)
	if r := post(t, fmt.Sprintf("%s/pause/%s/0", base, res.Hash), nil); r.StatusCode != http.StatusNoContent {
		t.Fatalf("pause: %d", r.StatusCode)
	}
	tt, _ := e.lookup(res.Hash)
	tt.AddClientPeer(p.seeder)
	time.Sleep(time.Second)
	if s := keepStats(t, base, res.Hash, 0); s.Done != 0 {
		t.Fatalf("paused file still came: %+v", s)
	}
	post(t, base+"/drop/"+res.Hash, nil)
	if _, ok := e.lookup(res.Hash); !ok {
		t.Fatal("a paused download was dropped")
	}
	post(t, fmt.Sprintf("%s/keep/%s/0", base, res.Hash), nil)
	waitDone(t, base, res.Hash, 0)
}

func TestLimitStepsAsideForStreams(t *testing.T) {
	p := newPack(t)
	e, base := newTestEngine(t)
	post(t, base+"/limit", map[string]int{"bytesPerSecond": 1 << 20})
	if got := e.limiter.Limit(); got != 1<<20 {
		t.Fatalf("limit: %v", got)
	}
	res := add(t, base, p.url, "")
	if got := e.limiter.Limit(); got != rate.Inf {
		t.Fatalf("a stream was limited: %v", got)
	}
	post(t, base+"/drop/"+res.Hash, nil)
	if got := e.limiter.Limit(); got != 1<<20 {
		t.Fatalf("limit after the stream: %v", got)
	}
	post(t, base+"/limit", map[string]int{"bytesPerSecond": 0})
	if got := e.limiter.Limit(); got != rate.Inf {
		t.Fatalf("no limit: %v", got)
	}
}

func TestDropLeavesKept(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, base := newTestEngine(t)
	hash := startKeep(t, e, base, p, dir, 0)
	post(t, base+"/drop/"+hash, nil)
	post(t, base+"/drop-all", nil)
	if _, ok := e.lookup(hash); !ok {
		t.Fatal("closing the player dropped a download")
	}
	waitDone(t, base, hash, 0)
}

func TestAddStreamingWithDirConflicts(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	_, base := newTestEngine(t)
	add(t, base, p.url, "")
	if r := post(t, base+"/add", map[string]string{"uri": p.url, "dir": dir}); r.StatusCode != http.StatusConflict {
		t.Fatalf("add: %d", r.StatusCode)
	}
}

func TestStreamingAKeptTorrentIsAllowed(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	_, base := newTestEngine(t)
	res := add(t, base, p.url, dir)
	if again := add(t, base, p.url, ""); again.Hash != res.Hash {
		t.Fatal("another torrent came back")
	}
}

func TestKeptSurvivesRestart(t *testing.T) {
	p := newPack(t)
	dir := keepDir(t)
	e, err := newEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", e.port)
	hash := startKeep(t, e, base, p, dir, 0)
	waitDone(t, base, hash, 0)
	e.client.Close()
	e.closeStorages()

	_, base2 := newTestEngine(t)
	res := add(t, base2, p.url, dir)
	post(t, fmt.Sprintf("%s/keep/%s/0", base2, res.Hash), nil)
	deadline := time.Now().Add(5 * time.Second)
	var s keepJSON
	for time.Now().Before(deadline) {
		if s = keepStats(t, base2, res.Hash, 0); s.Done == s.Total && s.Total > 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if s.Done != s.Total || s.Total == 0 {
		t.Fatalf("progress lost: %+v", s)
	}
}

func TestListenerComesBack(t *testing.T) {
	e, base := newTestEngine(t)
	e.closeListener()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if r, err := http.Get(base + "/stats/0000000000000000000000000000000000000000"); err == nil && r.StatusCode == http.StatusNotFound {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("the engine stopped answering")
}
