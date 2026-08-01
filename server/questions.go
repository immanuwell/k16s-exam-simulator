package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type Question struct {
	ID          string `yaml:"id"          json:"id"`
	Title       string `yaml:"title"        json:"title"`
	Weight      int    `yaml:"weight"       json:"weight"`
	Context     string `yaml:"context"      json:"context"`
	Description string `yaml:"description"  json:"description"`
	Hint        string `yaml:"hint"         json:"hint"`
}

// loadAllQuestions reads *.yaml files from examDir/<profile>/ for each profile subdir.
func loadAllQuestions(examDir string) (map[string][]Question, error) {
	entries, err := os.ReadDir(examDir)
	if err != nil {
		return nil, err
	}
	result := map[string][]Question{}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		profile := e.Name()
		qs, err := loadProfileQuestions(filepath.Join(examDir, profile))
		if err != nil {
			return nil, fmt.Errorf("profile %s: %w", profile, err)
		}
		if len(qs) > 0 {
			result[profile] = qs
		}
	}
	return result, nil
}

func loadProfileQuestions(dir string) ([]Question, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, err
	}
	var questions []Question
	for _, f := range files {
		data, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		var q Question
		if err := yaml.Unmarshal(data, &q); err != nil {
			return nil, fmt.Errorf("parse %s: %w", f, err)
		}
		if q.ID == "" {
			base := filepath.Base(f)
			q.ID = strings.TrimSuffix(base, ".yaml")
		}
		questions = append(questions, q)
	}
	return questions, nil
}

func findQuestion(questions []Question, id string) *Question {
	for i := range questions {
		if questions[i].ID == id {
			return &questions[i]
		}
	}
	return nil
}
