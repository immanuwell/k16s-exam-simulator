package main

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strings"
)

//go:embed all:frontend/build
var frontendFiles embed.FS

func main() {
	port := envOr("K16S_PORT", "8080")
	dbPath := envOr("K16S_DB", "/var/lib/k16s/k16s.db")
	examDir := envOr("K16S_EXAM_DIR", "/var/lib/k16s/exams")

	db := mustOpenDB(dbPath)
	defer db.Close()

	questions, err := loadAllQuestions(examDir)
	if err != nil {
		log.Printf("warning: could not load questions from %s: %v", examDir, err)
		questions = map[string][]Question{}
	}

	// Answer directories must belong to the candidate before the first question
	// is opened — Setup is a per-question button and may never be pressed.
	ensureAllWorkspaces(questions, examDir)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/status", handleStatus(db, questions))
	mux.HandleFunc("GET /api/session", handleGetSession(db))
	mux.HandleFunc("POST /api/session/start", handleStartSession(db, questions))
	mux.HandleFunc("POST /api/session/end", handleEndSession(db))
	mux.HandleFunc("GET /api/questions", handleListQuestions(questions))
	mux.HandleFunc("POST /api/questions/{id}/check", handleCheck(db, questions, examDir))
	mux.HandleFunc("POST /api/questions/{id}/setup", handleSetup(db, questions, examDir))

	sub, err := fs.Sub(frontendFiles, "frontend/build")
	if err != nil {
		log.Fatal(err)
	}
	mux.Handle("/", spaHandler(sub))

	log.Printf("k16s-server listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, corsMiddleware(mux)))
}

func spaHandler(fsys fs.FS) http.Handler {
	srv := http.FileServer(http.FS(fsys))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		upath := strings.TrimPrefix(r.URL.Path, "/")
		if upath == "" {
			upath = "index.html"
		}
		_, err := fsys.Open(upath)
		if err != nil {
			r2 := r.Clone(r.Context())
			r2.URL.Path = "/"
			srv.ServeHTTP(w, r2)
			return
		}
		srv.ServeHTTP(w, r)
	})
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
