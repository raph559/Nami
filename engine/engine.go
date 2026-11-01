// Package main is the Nami torrent engine, built as a C archive and linked
// into the iOS app. It exposes a small HTTP API on 127.0.0.1 that the Swift
// side and the video player talk to.
package main

import "C"

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/storage"
)

type engine struct {
	client   *torrent.Client
	dataDir  string
	port     int
	mux      *http.ServeMux
	mu       sync.Mutex
	last     map[string]time.Time
	listener net.Listener
	// Torrents being downloaded to keep: the player cannot drop them.
	kept     map[string]*keptTorrent
	storages map[string]storage.ClientImplCloser
}

// keptTorrent lives in its own dir, so it outlives a restart; files are the
// indexes still wanted.
type keptTorrent struct {
	dir   string
	files map[int]bool
}

var errBusy = errors.New("torrent is being streamed")

var (
	startOnce sync.Once
	port      int
	startErr  error
)

//export NamiStart
func NamiStart(dataDir *C.char) C.int {
	dir := C.GoString(dataDir)
	startOnce.Do(func() { port, startErr = start(dir) })
	if startErr != nil {
		log.Printf("nami: start failed: %v", startErr)
		return -1
	}
	return C.int(port)
}

func start(dir string) (int, error) {
	e, err := newEngine(dir)
	if err != nil {
		return 0, err
	}
	return e.port, nil
}

func newEngine(dir string) (*engine, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dir
	streams := storage.NewFileByInfoHash(dir)
	cfg.DefaultStorage = streams
	cfg.Seed = false
	cfg.ListenPort = 0
	cfg.EstablishedConnsPerTorrent = 60
	cl, err := torrent.NewClient(cfg)
	if err != nil {
		return nil, err
	}
	e := &engine{
		client: cl, dataDir: dir, last: map[string]time.Time{},
		kept: map[string]*keptTorrent{}, storages: map[string]storage.ClientImplCloser{dir: streams},
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /add", e.handleAdd)
	mux.HandleFunc("GET /stream/{hash}/{index}", e.handleStream)
	mux.HandleFunc("GET /stats/{hash}", e.handleStats)
	mux.HandleFunc("POST /drop/{hash}", e.handleDrop)
	mux.HandleFunc("POST /drop-all", e.handleDropAll)
	mux.HandleFunc("POST /keep/{hash}/{index}", e.handleKeep)
	mux.HandleFunc("GET /keep/{hash}/{index}", e.handleKeepStats)
	mux.HandleFunc("POST /finish/{hash}/{index}", e.handleFinish)
	mux.HandleFunc("POST /pause/{hash}/{index}", e.handlePause)
	mux.HandleFunc("POST /unkeep/{hash}/{index}", e.handleUnkeep)
	e.mux = mux
	e.listener = ln
	e.port = ln.Addr().(*net.TCPAddr).Port
	go e.serve()
	return e, nil
}

// serve keeps the API on its port: iOS can close the socket while the app is
// suspended, and the players and the app only know that port.
func (e *engine) serve() {
	for {
		e.mu.Lock()
		ln := e.listener
		e.mu.Unlock()
		log.Println(http.Serve(ln, e.mux))
		for {
			next, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", e.port))
			if err == nil {
				e.mu.Lock()
				e.listener = next
				e.mu.Unlock()
				break
			}
			time.Sleep(time.Second)
		}
	}
}

func (e *engine) closeListener() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.listener.Close()
}

func (e *engine) closeStorages() {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, s := range e.storages {
		s.Close()
	}
}

type fileJSON struct {
	Index  int    `json:"index"`
	Path   string `json:"path"`
	Length int64  `json:"length"`
}

type addResult struct {
	Hash  string     `json:"hash"`
	Name  string     `json:"name"`
	Files []fileJSON `json:"files"`
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, err error) {
	writeJSON(w, code, map[string]string{"error": err.Error()})
}

// handleAdd accepts {"uri": "magnet:..." | "https://.../x.torrent"} and waits
// for the metadata so the caller can pick a file. With "dir", the torrent is
// kept in that folder instead of the stream folder.
func (e *engine) handleAdd(w http.ResponseWriter, r *http.Request) {
	var body struct {
		URI string `json:"uri"`
		Dir string `json:"dir"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.URI == "" {
		writeErr(w, http.StatusBadRequest, errors.New("missing uri"))
		return
	}
	t, err := e.addURI(r.Context(), body.URI, body.Dir)
	if errors.Is(err, errBusy) {
		writeErr(w, http.StatusConflict, err)
		return
	}
	if err != nil {
		writeErr(w, http.StatusBadGateway, err)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	select {
	case <-t.GotInfo():
	case <-ctx.Done():
		e.mu.Lock()
		delete(e.kept, t.InfoHash().HexString())
		e.mu.Unlock()
		t.Drop()
		writeErr(w, http.StatusGatewayTimeout, errors.New("no peers sent metadata in time"))
		return
	}
	res := addResult{Hash: t.InfoHash().HexString(), Name: t.Name()}
	for i, f := range t.Files() {
		res.Files = append(res.Files, fileJSON{Index: i, Path: f.DisplayPath(), Length: f.Length()})
	}
	e.touch(res.Hash)
	writeJSON(w, http.StatusOK, res)
}

// Public trackers added to every torrent; sources that only give an info hash
// would otherwise depend on the DHT alone.
var extraTrackers = [][]string{{
	"udp://tracker.opentrackr.org:1337/announce",
	"http://nyaa.tracker.wf:7777/announce",
	"udp://open.stealth.si:80/announce",
	"udp://tracker.torrent.eu.org:451/announce",
	"udp://exodus.desync.com:6969/announce",
	"udp://open.demonii.com:1337/announce",
}}

func (e *engine) addURI(ctx context.Context, uri, dir string) (*torrent.Torrent, error) {
	spec, err := e.spec(ctx, uri)
	if err != nil {
		return nil, err
	}
	if dir != "" {
		if spec.Storage, err = e.storageFor(dir); err != nil {
			return nil, err
		}
	}
	t, isNew, err := e.client.AddTorrentSpec(spec)
	if err != nil {
		return nil, err
	}
	hash := t.InfoHash().HexString()
	e.mu.Lock()
	defer e.mu.Unlock()
	if dir != "" {
		if _, kept := e.kept[hash]; !isNew && !kept {
			return nil, errBusy
		}
		if isNew {
			e.kept[hash] = &keptTorrent{dir: dir, files: map[int]bool{}}
		}
	}
	t.AddTrackers(extraTrackers)
	return t, nil
}

func (e *engine) storageFor(dir string) (storage.ClientImpl, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	if s, ok := e.storages[dir]; ok {
		return s, nil
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	s := storage.NewFileByInfoHash(dir)
	e.storages[dir] = s
	return s, nil
}

func (e *engine) spec(ctx context.Context, uri string) (*torrent.TorrentSpec, error) {
	if strings.HasPrefix(uri, "magnet:") {
		return torrent.TorrentSpecFromMagnetUri(uri)
	}
	if len(uri) == 40 {
		if _, err := strconv.ParseUint(uri[:8], 16, 64); err == nil {
			return torrent.TorrentSpecFromMagnetUri("magnet:?xt=urn:btih:" + uri)
		}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, uri, nil)
	if err != nil {
		return nil, err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("torrent download: HTTP %d", resp.StatusCode)
	}
	mi, err := metainfo.Load(io.LimitReader(resp.Body, 20<<20))
	if err != nil {
		return nil, err
	}
	return torrent.TorrentSpecFromMetaInfoErr(mi)
}

func (e *engine) lookup(hash string) (*torrent.Torrent, bool) {
	var ih metainfo.Hash
	if err := ih.FromHexString(hash); err != nil {
		return nil, false
	}
	return e.client.Torrent(ih)
}

func (e *engine) touch(hash string) {
	e.mu.Lock()
	e.last[hash] = time.Now()
	e.mu.Unlock()
}

// handleStream serves one file of a torrent with HTTP range support; pieces
// are prioritised around the read position so playback can start early.
func (e *engine) handleStream(w http.ResponseWriter, r *http.Request) {
	t, ok := e.lookup(r.PathValue("hash"))
	if !ok {
		http.NotFound(w, r)
		return
	}
	<-t.GotInfo()
	idx, err := strconv.Atoi(r.PathValue("index"))
	files := t.Files()
	if err != nil || idx < 0 || idx >= len(files) {
		http.NotFound(w, r)
		return
	}
	f := files[idx]
	e.touch(r.PathValue("hash"))
	rd := f.NewReader()
	defer rd.Close()
	rd.SetResponsive()
	rd.SetReadahead(16 << 20)
	rd.SetContext(r.Context())
	http.ServeContent(w, r, filepath.Base(f.DisplayPath()), time.Time{}, rd)
}

type statsJSON struct {
	Peers      int     `json:"peers"`
	Seeders    int     `json:"seeders"`
	Downloaded int64   `json:"downloaded"`
	Total      int64   `json:"total"`
	Progress   float64 `json:"progress"`
}

func (e *engine) handleStats(w http.ResponseWriter, r *http.Request) {
	t, ok := e.lookup(r.PathValue("hash"))
	if !ok {
		http.NotFound(w, r)
		return
	}
	s := t.Stats()
	out := statsJSON{Peers: s.ActivePeers, Seeders: s.ConnectedSeeders}
	if t.Info() != nil {
		out.Total = t.Length()
		out.Downloaded = t.BytesCompleted()
		if out.Total > 0 {
			out.Progress = float64(out.Downloaded) / float64(out.Total)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (e *engine) drop(t *torrent.Torrent) {
	hash := t.InfoHash().HexString()
	t.Drop()
	_ = os.RemoveAll(filepath.Join(e.dataDir, hash))
	e.mu.Lock()
	delete(e.last, hash)
	e.mu.Unlock()
}

func (e *engine) isKept(hash string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	_, ok := e.kept[hash]
	return ok
}

func (e *engine) handleDrop(w http.ResponseWriter, r *http.Request) {
	if t, ok := e.lookup(r.PathValue("hash")); ok && !e.isKept(r.PathValue("hash")) {
		e.drop(t)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (e *engine) handleDropAll(w http.ResponseWriter, r *http.Request) {
	for _, t := range e.client.Torrents() {
		if !e.isKept(t.InfoHash().HexString()) {
			e.drop(t)
		}
	}
	w.WriteHeader(http.StatusNoContent)
}

// keptFile finds a file of a kept torrent, answering the request when it cannot.
func (e *engine) keptFile(w http.ResponseWriter, r *http.Request) (*torrent.Torrent, *torrent.File, int, bool) {
	t, ok := e.lookup(r.PathValue("hash"))
	if !ok || !e.isKept(r.PathValue("hash")) {
		http.NotFound(w, r)
		return nil, nil, 0, false
	}
	<-t.GotInfo()
	idx, err := strconv.Atoi(r.PathValue("index"))
	files := t.Files()
	if err != nil || idx < 0 || idx >= len(files) {
		http.NotFound(w, r)
		return nil, nil, 0, false
	}
	return t, files[idx], idx, true
}

// handleKeep asks for the pieces of one file only.
func (e *engine) handleKeep(w http.ResponseWriter, r *http.Request) {
	t, f, idx, ok := e.keptFile(w, r)
	if !ok {
		return
	}
	f.Download()
	e.mu.Lock()
	e.kept[t.InfoHash().HexString()].files[idx] = true
	e.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// handlePause stops asking for a file; /keep asks again.
func (e *engine) handlePause(w http.ResponseWriter, r *http.Request) {
	_, f, _, ok := e.keptFile(w, r)
	if !ok {
		return
	}
	f.SetPriority(torrent.PiecePriorityNone)
	w.WriteHeader(http.StatusNoContent)
}

type keepJSON struct {
	Done  int64 `json:"done"`
	Total int64 `json:"total"`
	Peers int   `json:"peers"`
}

func (e *engine) handleKeepStats(w http.ResponseWriter, r *http.Request) {
	t, f, _, ok := e.keptFile(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, keepJSON{Done: f.BytesCompleted(), Total: f.Length(), Peers: t.Stats().ActivePeers})
}

// release stops keeping a file and closes the torrent with its last one. The
// caller removes the partial data once it is done with the files.
func (e *engine) release(t *torrent.Torrent, idx int) (dir string, closed bool) {
	hash := t.InfoHash().HexString()
	e.mu.Lock()
	k := e.kept[hash]
	dir = k.dir
	delete(k.files, idx)
	closed = len(k.files) == 0
	if closed {
		delete(e.kept, hash)
	}
	e.mu.Unlock()
	if closed {
		t.Drop()
		<-t.Closed()
	}
	return dir, closed
}

// handleFinish moves a finished file to {"dest": path}.
func (e *engine) handleFinish(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Dest string `json:"dest"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.Dest == "" {
		writeErr(w, http.StatusBadRequest, errors.New("missing dest"))
		return
	}
	t, f, idx, ok := e.keptFile(w, r)
	if !ok {
		return
	}
	if f.BytesCompleted() != f.Length() {
		writeErr(w, http.StatusConflict, errors.New("file is not complete"))
		return
	}
	hash := t.InfoHash().HexString()
	e.mu.Lock()
	dir := e.kept[hash].dir
	e.mu.Unlock()
	src := filepath.Join(dir, hash, filepath.FromSlash(f.Path()))
	// The storage names a file .part until it gets round to renaming it.
	if _, err := os.Stat(src); err != nil {
		src += ".part"
	}
	// With the last file the torrent closes first, so nothing holds it open.
	dir, closed := e.release(t, idx)
	if err := moveFile(src, body.Dest, closed); err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	if closed {
		removeAll(filepath.Join(dir, hash))
	}
	w.WriteHeader(http.StatusNoContent)
}

// On Windows a closed torrent keeps its mapped files a moment longer.
const releaseWait = 3 * time.Second

func removeAll(path string) {
	deadline := time.Now().Add(releaseWait)
	for os.RemoveAll(path) != nil && time.Now().Before(deadline) {
		time.Sleep(100 * time.Millisecond)
	}
}

// moveFile renames, or copies when the torrent still holds the file open.
func moveFile(src, dest string, closed bool) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	deadline := time.Now().Add(releaseWait)
	for {
		if os.Rename(src, dest) == nil {
			return nil
		}
		if !closed || !time.Now().Before(deadline) {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(dest)
		return err
	}
	return out.Close()
}

// handleUnkeep cancels a file; an unknown torrent has nothing left to cancel.
func (e *engine) handleUnkeep(w http.ResponseWriter, r *http.Request) {
	hash := r.PathValue("hash")
	t, ok := e.lookup(hash)
	if !ok || !e.isKept(hash) {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	idx, err := strconv.Atoi(r.PathValue("index"))
	if err == nil && t.Info() != nil && idx >= 0 && idx < len(t.Files()) {
		t.Files()[idx].SetPriority(torrent.PiecePriorityNone)
	}
	if dir, closed := e.release(t, idx); closed {
		removeAll(filepath.Join(dir, hash))
	}
	w.WriteHeader(http.StatusNoContent)
}

func main() {}
