package main

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func newTestServer(t *testing.T, ready bool) *httptest.Server {
	t.Helper()
	var r atomic.Bool
	r.Store(ready)
	logger := slog.New(slog.NewJSONHandler(io.Discard, nil))
	srv := httptest.NewServer(newHandler("Hi", &r, logger))
	t.Cleanup(srv.Close)
	return srv
}

func TestRoot(t *testing.T) {
	srv := newTestServer(t, true)

	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["message"] != "Hi from GKE" {
		t.Errorf("message = %q, want %q", body["message"], "Hi from GKE")
	}
	if body["version"] != version {
		t.Errorf("version = %q, want %q", body["version"], version)
	}
}

func TestProbes(t *testing.T) {
	tests := []struct {
		name  string
		ready bool
		path  string
		want  int
	}{
		{"liveness", true, "/healthz", http.StatusOK},
		{"liveness while draining", false, "/healthz", http.StatusOK},
		{"readiness", true, "/readyz", http.StatusOK},
		{"readiness while draining", false, "/readyz", http.StatusServiceUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			srv := newTestServer(t, tt.ready)
			resp, err := http.Get(srv.URL + tt.path)
			if err != nil {
				t.Fatal(err)
			}
			resp.Body.Close()
			if resp.StatusCode != tt.want {
				t.Errorf("GET %s status = %d, want %d", tt.path, resp.StatusCode, tt.want)
			}
		})
	}
}

func TestUnknownRoutes(t *testing.T) {
	srv := newTestServer(t, true)

	resp, err := http.Get(srv.URL + "/nope")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("GET /nope status = %d, want 404", resp.StatusCode)
	}

	resp, err = http.Post(srv.URL+"/", "text/plain", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("POST / status = %d, want 405", resp.StatusCode)
	}
}
