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
	client  *torrent.Client
	dataDir string
	mu      sync.Mutex
	last    map[string]time.Time
}

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
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, err
	}
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dir
	cfg.DefaultStorage = storage.NewFileByInfoHash(dir)
	cfg.Seed = false
	cfg.ListenPort = 0
	cfg.EstablishedConnsPerTorrent = 60
	cl, err := torrent.NewClient(cfg)
	if err != nil {
		return 0, err
	}
	e := &engine{client: cl, dataDir: dir, last: map[string]time.Time{}}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST /add", e.handleAdd)
	mux.HandleFunc("GET /stream/{hash}/{index}", e.handleStream)
	mux.HandleFunc("GET /stats/{hash}", e.handleStats)
	mux.HandleFunc("POST /drop/{hash}", e.handleDrop)
	mux.HandleFunc("POST /drop-all", e.handleDropAll)
	go func() { log.Println(http.Serve(ln, mux)) }()
	return ln.Addr().(*net.TCPAddr).Port, nil
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
// for the metadata so the caller can pick a file.
func (e *engine) handleAdd(w http.ResponseWriter, r *http.Request) {
	var body struct {
		URI string `json:"uri"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.URI == "" {
		writeErr(w, http.StatusBadRequest, errors.New("missing uri"))
		return
	}
	t, err := e.addURI(r.Context(), body.URI)
	if err != nil {
		writeErr(w, http.StatusBadGateway, err)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	select {
	case <-t.GotInfo():
	case <-ctx.Done():
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

func (e *engine) addURI(ctx context.Context, uri string) (*torrent.Torrent, error) {
	t, err := e.addRaw(ctx, uri)
	if err == nil {
		t.AddTrackers(extraTrackers)
	}
	return t, err
}

func (e *engine) addRaw(ctx context.Context, uri string) (*torrent.Torrent, error) {
	if strings.HasPrefix(uri, "magnet:") {
		return e.client.AddMagnet(uri)
	}
	if len(uri) == 40 {
		if _, err := strconv.ParseUint(uri[:8], 16, 64); err == nil {
			return e.client.AddMagnet("magnet:?xt=urn:btih:" + uri)
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
	return e.client.AddTorrent(mi)
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

func (e *engine) handleDrop(w http.ResponseWriter, r *http.Request) {
	if t, ok := e.lookup(r.PathValue("hash")); ok {
		e.drop(t)
	}
	w.WriteHeader(http.StatusNoContent)
}

func (e *engine) handleDropAll(w http.ResponseWriter, r *http.Request) {
	for _, t := range e.client.Torrents() {
		e.drop(t)
	}
	w.WriteHeader(http.StatusNoContent)
}

func main() {}
