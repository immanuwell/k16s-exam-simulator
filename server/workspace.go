package main

import (
	"log"
	"os"
	"os/user"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Exam questions tell the candidate to save their answer under /opt/<workspace>
// — "Save the node's status condition reason to /opt/cka/node01-fix.txt". The
// setup scripts run as root, so `mkdir -p /opt/cka` leaves the directory
// root-owned and 0755 and the candidate's shell redirect dies with:
//
//	-bash: /opt/cka/node01-fix.txt: Permission denied
//
// Several setup scripts also drop root-owned 0600 key material in there that the
// task expects the candidate to read (the PKI questions), which fails the same
// way. Hand the workspaces to the candidate instead.
//
// The paths are derived from the exam content rather than hardcoded, so new
// questions are covered automatically. /opt is shared with cni, containerd and
// incus, which must stay root-owned — hence the explicit denylist below.

const candidateUser = "candidate"

// optPathRe matches any /opt path mentioned in question text or a shell script.
// Only the first component after /opt is used, so a file reference like
// /opt/cka/node01-fix.txt resolves to the /opt/cka workspace.
var optPathRe = regexp.MustCompile(`/opt/([A-Za-z0-9._-]+)`)

// systemOptDirs are provisioned by the installer and are not exam workspaces.
// Chowning these to the candidate would hand over the container runtime.
var systemOptDirs = map[string]bool{
	"cni":        true,
	"containerd": true,
	"incus":      true,
	"go":         true,
	"novnc":      true,
}

// workspacesIn extracts the exam workspace directories referenced by the given
// text, skipping system directories.
func workspacesIn(texts ...string) []string {
	seen := map[string]bool{}
	for _, text := range texts {
		for _, m := range optPathRe.FindAllStringSubmatch(text, -1) {
			name := m[1]
			if systemOptDirs[name] || strings.HasPrefix(name, ".") {
				continue
			}
			seen["/opt/"+name] = true
		}
	}
	out := make([]string, 0, len(seen))
	for path := range seen {
		out = append(out, path)
	}
	sort.Strings(out)
	return out
}

// questionWorkspaces collects workspaces named by a question's own text and by
// its setup and validate scripts.
func questionWorkspaces(q Question, examDir, profile string) []string {
	texts := []string{q.Description, q.Hint}
	for _, name := range []string{"setup.sh", "validate.sh"} {
		script := filepath.Join(examDir, profile, "scripts", q.ID, name)
		if b, err := os.ReadFile(script); err == nil {
			texts = append(texts, string(b))
		}
	}
	return workspacesIn(texts...)
}

// candidateIDs resolves the candidate account's uid/gid. It returns ok=false on
// a workstation where the account does not exist, so tests and local runs of the
// server do not fail.
func candidateIDs() (uid, gid int, ok bool) {
	u, err := user.Lookup(candidateUser)
	if err != nil {
		return 0, 0, false
	}
	uid, err1 := strconv.Atoi(u.Uid)
	gid, err2 := strconv.Atoi(u.Gid)
	if err1 != nil || err2 != nil {
		return 0, 0, false
	}
	return uid, gid, true
}

// ensureWorkspaces creates each workspace and gives it to the candidate,
// recursively so that files a setup script wrote as root become writable too.
func ensureWorkspaces(paths []string) {
	if len(paths) == 0 {
		return
	}
	uid, gid, ok := candidateIDs()
	if !ok {
		return
	}
	for _, path := range paths {
		if err := os.MkdirAll(path, 0o755); err != nil {
			log.Printf("workspace %s: mkdir: %v", path, err)
			continue
		}
		err := filepath.Walk(path, func(p string, _ os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			return os.Lchown(p, uid, gid)
		})
		if err != nil {
			log.Printf("workspace %s: chown: %v", path, err)
		}
	}
}

// ensureAllWorkspaces prepares every workspace the loaded exam content mentions.
// Called at startup because the candidate can start writing to a question's
// answer path without first pressing the per-question Setup button.
func ensureAllWorkspaces(questions map[string][]Question, examDir string) {
	var all []string
	for profile, qs := range questions {
		for _, q := range qs {
			all = append(all, questionWorkspaces(q, examDir, profile)...)
		}
	}
	paths := workspacesIn(strings.Join(all, "\n"))
	ensureWorkspaces(paths)
	if len(paths) > 0 {
		log.Printf("exam workspaces ready for %s: %s", candidateUser, strings.Join(paths, " "))
	}
}
