package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/google/uuid"
)

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// GET /api/status
func handleStatus(db *sql.DB, questions map[string][]Question) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		session, _ := getActiveSession(db)
		profiles := make([]string, 0, len(questions))
		for p := range questions {
			profiles = append(profiles, p)
		}
		writeJSON(w, map[string]any{
			"ok":       true,
			"session":  session,
			"profiles": profiles,
		})
	}
}

// GET /api/session
func handleGetSession(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		session, err := getActiveSession(db)
		if err != nil {
			writeError(w, 500, err.Error())
			return
		}
		if session == nil {
			writeError(w, 404, "no active session")
			return
		}
		writeJSON(w, session)
	}
}

// POST /api/session/start   body: {"profile":"cka","duration_secs":7200}
func handleStartSession(db *sql.DB, questions map[string][]Question) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Profile      string `json:"profile"`
			DurationSecs int    `json:"duration_secs"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, 400, "invalid request body")
			return
		}
		if req.Profile == "" {
			req.Profile = "cka"
		}
		if req.DurationSecs <= 0 {
			req.DurationSecs = 7200
		}
		if _, ok := questions[req.Profile]; !ok {
			writeError(w, 400, "unknown profile: "+req.Profile)
			return
		}

		// End any running session before starting a new one.
		if existing, _ := getActiveSession(db); existing != nil {
			_ = endSession(db, existing.ID)
		}

		id := uuid.New().String()
		if err := createSession(db, id, req.Profile, req.DurationSecs); err != nil {
			writeError(w, 500, err.Error())
			return
		}
		session, err := getSession(db, id)
		if err != nil {
			writeError(w, 500, err.Error())
			return
		}
		writeJSON(w, map[string]any{"session": session})
	}
}

// POST /api/session/end
func handleEndSession(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		session, err := getActiveSession(db)
		if err != nil || session == nil {
			writeError(w, 404, "no active session")
			return
		}
		if err := endSession(db, session.ID); err != nil {
			writeError(w, 500, err.Error())
			return
		}
		session, _ = getSession(db, session.ID)
		writeJSON(w, map[string]any{"session": session})
	}
}

// GET /api/questions?profile=cka
func handleListQuestions(questions map[string][]Question) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		profile := r.URL.Query().Get("profile")
		if profile == "" {
			profile = "cka"
		}
		qs, ok := questions[profile]
		if !ok {
			writeError(w, 404, "unknown profile: "+profile)
			return
		}
		writeJSON(w, map[string]any{"questions": qs})
	}
}

// POST /api/questions/{id}/check
func handleCheck(db *sql.DB, questions map[string][]Question, examDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")

		session, err := getActiveSession(db)
		if err != nil || session == nil {
			writeError(w, 400, "no active session")
			return
		}
		if findQuestion(questions[session.Profile], id) == nil {
			writeError(w, 404, "question not found: "+id)
			return
		}

		script := filepath.Join(examDir, session.Profile, "scripts", id, "validate.sh")
		if _, err := os.Stat(script); err != nil {
			writeError(w, 404, "no validate script for: "+id)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()

		cmd := exec.CommandContext(ctx, "bash", script)
		cmd.Env = append(os.Environ(), "KUBECONFIG=/etc/kubernetes/admin.conf")
		out, err := cmd.CombinedOutput()
		passed := err == nil

		status := "failed"
		if passed {
			status = "passed"
		}
		if dbErr := upsertProgress(db, session.ID, id, status, string(out)); dbErr != nil {
			log.Printf("upsertProgress: %v", dbErr)
		}

		writeJSON(w, map[string]any{
			"passed": passed,
			"output": string(out),
		})
	}
}

// POST /api/questions/{id}/setup
func handleSetup(db *sql.DB, examDir string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")

		session, err := getActiveSession(db)
		if err != nil || session == nil {
			writeError(w, 400, "no active session")
			return
		}

		script := filepath.Join(examDir, session.Profile, "scripts", id, "setup.sh")
		if _, err := os.Stat(script); err != nil {
			writeJSON(w, map[string]any{"ok": true, "output": "No environment setup needed for this task."})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()

		cmd := exec.CommandContext(ctx, "bash", script)
		cmd.Env = append(os.Environ(), "KUBECONFIG=/etc/kubernetes/admin.conf")
		out, err := cmd.CombinedOutput()
		if err != nil {
			writeJSON(w, map[string]any{"ok": false, "output": string(out)})
			return
		}

		// Mark as attempted so the question nav shows it's been started.
		if dbErr := upsertProgress(db, session.ID, id, "attempted", ""); dbErr != nil {
			log.Printf("upsertProgress: %v", dbErr)
		}

		writeJSON(w, map[string]any{"ok": true, "output": string(out)})
	}
}
