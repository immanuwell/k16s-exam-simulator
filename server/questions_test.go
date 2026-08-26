package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Exam scripts that shell out to `incus exec` reach a worker node container
// through Incus, which only exists in the VM+Incus and Lima (laptop) install
// modes. Lightweight mode runs workers as kind/Docker containers instead and
// has no `incus` binary anywhere in its stack, so such a script fails with
// "incus: command not found" the moment a candidate clicks Setup Env or Check
// Answer. The `requires: heavy` marker on a question's YAML is how the exam
// UI already hides a question and excludes it from scoring in that case (see
// unavailableReason in handlers.go) — every question whose scripts use
// `incus exec` needs that marker, or lightweight-mode candidates hit a broken
// question with no explanation.
func TestIncusExecRequiresHeavy(t *testing.T) {
	examDir := "../exams"
	profiles, err := os.ReadDir(examDir)
	if err != nil {
		t.Fatalf("read %s: %v", examDir, err)
	}

	for _, p := range profiles {
		if !p.IsDir() {
			continue
		}
		profile := p.Name()
		questions, err := loadProfileQuestions(filepath.Join(examDir, profile))
		if err != nil {
			t.Fatalf("load questions for %s: %v", profile, err)
		}
		byID := map[string]Question{}
		for _, q := range questions {
			byID[q.ID] = q
		}

		scriptsDir := filepath.Join(examDir, profile, "scripts")
		entries, err := os.ReadDir(scriptsDir)
		if err != nil {
			continue
		}
		for _, e := range entries {
			if !e.IsDir() {
				continue
			}
			id := e.Name()
			for _, script := range []string{"setup.sh", "validate.sh"} {
				path := filepath.Join(scriptsDir, id, script)
				data, err := os.ReadFile(path)
				if err != nil {
					continue
				}
				if !strings.Contains(string(data), "incus exec") {
					continue
				}
				q, ok := byID[id]
				if !ok {
					t.Errorf("%s: uses `incus exec` but no matching question %q in profile %q", path, id, profile)
					continue
				}
				if q.Requires != "heavy" {
					t.Errorf("%s: uses `incus exec`, which needs the VM+Incus/Lima install modes, but %s/%s.yaml has no `requires: heavy` — Setup Env/Check Answer will fail with \"incus: command not found\" under lightweight mode", path, profile, id)
				}
			}
		}
	}
}
