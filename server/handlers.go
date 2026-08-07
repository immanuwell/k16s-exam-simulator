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

// unavailableReason explains why a question can't run under the given mode,
// or "" if it's fine. Only one case exists today (AppArmor needing kernel
// securityfs that Docker containers don't expose), but the shape leaves
// room for other requires values without changing callers.
func unavailableReason(q *Question, mode string) string {
	if mode != "lightweight" || q.Requires != "heavy" {
		return ""
	}
	return "This task needs the full VM-based install (kubeadm + Incus or Lima) — its environment can't be created under the lightweight (kind) mode."
}

// GET /api/status
func handleStatus(db *sql.DB, questions map[string][]Question, mode string) http.HandlerFunc {
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
			"mode":     mode,
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
func handleCheck(db *sql.DB, questions map[string][]Question, examDir string, mode string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")

		session, err := getActiveSession(db)
		if err != nil || session == nil {
			writeError(w, 400, "no active session")
			return
		}
		q := findQuestion(questions[session.Profile], id)
		if q == nil {
			writeError(w, 404, "question not found: "+id)
			return
		}
		if reason := unavailableReason(q, mode); reason != "" {
			writeJSON(w, map[string]any{"unavailable": true, "reason": reason})
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
func handleSetup(db *sql.DB, examDir string, questions map[string][]Question, mode string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")

		session, err := getActiveSession(db)
		if err != nil || session == nil {
			writeError(w, 400, "no active session")
			return
		}
		if q := findQuestion(questions[session.Profile], id); q != nil {
			if reason := unavailableReason(q, mode); reason != "" {
				writeJSON(w, map[string]any{"unavailable": true, "reason": reason})
				return
			}
		}

		script := filepath.Join(examDir, session.Profile, "scripts", id, "setup.sh")
		if _, err := os.Stat(script); err != nil {
			writeJSON(w, map[string]any{"ok": true, "output": "No environment setup needed for this task."})
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
		defer cancel()

		beforeOpt := listOptEntries()

		cmd := exec.CommandContext(ctx, "bash", script)
		cmd.Env = append(os.Environ(), "KUBECONFIG=/etc/kubernetes/admin.conf")
		out, err := cmd.CombinedOutput()

		// setup.sh runs as root (k16s-server's own systemd unit is
		// User=root), so any /opt/<topic> scratch directory it creates —
		// nearly every question has one — comes out root-owned, 755. The
		// candidate user the exam terminal actually runs as then can't
		// write their answer into it, and for the PKI questions that seed
		// an input key file (0600, root-owned) can't even read it. Neither
		// showed up in testing before because grading was always exercised
		// as root over SSH directly, never as the actual restricted
		// candidate — confirmed by trying it that way, not assumed.
		// Only newly-created top-level /opt entries are touched, so this
		// never reaches pre-existing content already under /opt (e.g. the
		// repo checkout itself at /opt/k16s in --host mode), and it runs
		// regardless of setup.sh's exit status since a partial failure can
		// still have left a partially-built, inaccessible directory behind.
		chownNewOptEntries(beforeOpt)

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

// listOptEntries snapshots /opt's top-level entry names so a later call can
// tell what setup.sh just created versus what was already there.
func listOptEntries() map[string]bool {
	names := map[string]bool{}
	entries, err := os.ReadDir("/opt")
	if err != nil {
		return names // /opt not existing yet is fine — everything after is "new"
	}
	for _, e := range entries {
		names[e.Name()] = true
	}
	return names
}

// chownNewOptEntries hands ownership of whatever setup.sh just added under
// /opt to the candidate user, recursively. See handleSetup for why.
func chownNewOptEntries(before map[string]bool) {
	entries, err := os.ReadDir("/opt")
	if err != nil {
		return
	}
	for _, e := range entries {
		if before[e.Name()] {
			continue
		}
		path := filepath.Join("/opt", e.Name())
		if err := exec.Command("chown", "-R", "candidate:candidate", path).Run(); err != nil {
			log.Printf("chown %s: %v", path, err)
		}
	}
}
