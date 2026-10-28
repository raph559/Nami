package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"testing"
)

// Streams the start of Sintel (Creative Commons) through the engine API.
func TestStreamSintel(t *testing.T) {
	p, err := start(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	base := fmt.Sprintf("http://127.0.0.1:%d", p)
	body, _ := json.Marshal(map[string]string{"uri": "https://webtorrent.io/torrents/sintel.torrent"})
	resp, err := http.Post(base+"/add", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	var res addResult
	if err := json.NewDecoder(resp.Body).Decode(&res); err != nil || resp.StatusCode != 200 {
		t.Fatalf("add: %d %v", resp.StatusCode, err)
	}
	t.Logf("torrent %s %q, %d files", res.Hash, res.Name, len(res.Files))
	video := -1
	for _, f := range res.Files {
		if bytes.HasSuffix([]byte(f.Path), []byte(".mp4")) {
			video = f.Index
		}
	}
	if video < 0 {
		t.Fatal("no mp4 in torrent")
	}
	req, _ := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/stream/%s/%d", base, res.Hash, video), nil)
	req.Header.Set("Range", "bytes=1000000-1999999")
	sr, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	n, err := io.Copy(io.Discard, sr.Body)
	if err != nil || sr.StatusCode != http.StatusPartialContent || n != 1000000 {
		t.Fatalf("stream: status %d, %d bytes, %v", sr.StatusCode, n, err)
	}
	st, _ := http.Get(base + "/stats/" + res.Hash)
	stats, _ := io.ReadAll(st.Body)
	t.Logf("range ok (%d bytes), stats %s", n, stats)
}
