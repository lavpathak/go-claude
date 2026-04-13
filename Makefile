.PHONY: help setup test test-v test-cover lint vet fmt check diff clean

## help: Show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'

## setup: First-time setup (install hooks, verify tools)
setup:
	@chmod +x scripts/setup-claude-guardrails.sh
	@./scripts/setup-claude-guardrails.sh

## test: Run all tests with race detection
test:
	go test -race -count=1 ./...

## test-v: Run all tests verbose
test-v:
	go test -race -count=1 -v ./...

## test-cover: Run tests with coverage report
test-cover:
	go test -race -count=1 -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Open coverage.html to view report"

## lint: Run golangci-lint
lint:
	golangci-lint run ./...

## vet: Run go vet
vet:
	go vet ./...

## fmt: Format all Go files
fmt:
	gofumpt -w .
	go fmt ./...

## check: Run all checks (same as CI)
check: fmt vet lint test
	@echo "✅ All checks passed"

## diff: Show staged file count vs limit
diff:
	@STAGED=$$(git diff --cached --name-only | wc -l); \
	echo "Staged: $$STAGED / 5 files"; \
	if [ "$$STAGED" -gt 5 ]; then echo "⚠️  Over limit!"; fi

## clean: Remove generated files
clean:
	rm -f coverage.out coverage.html
