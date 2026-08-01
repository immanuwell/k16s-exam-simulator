.PHONY: build frontend backend clean dev

build: frontend backend

frontend:
	cd frontend && npm install && npm run build

backend:
	go mod tidy && go build -o ckx-server .

clean:
	rm -f ckx-server
	rm -rf frontend/build frontend/node_modules

# Run locally against the live cluster (set KUBECONFIG first)
dev: frontend
	CKX_PORT=8080 CKX_EXAM_DIR=../exams CKX_DB=/tmp/ckx-dev.db go run .
