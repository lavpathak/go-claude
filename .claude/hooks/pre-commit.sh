#!/usr/bin/env bash
# .claude/hooks/pre-commit.sh
# Install: cp .claude/hooks/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo "🔍 Running pre-commit guardrails..."

# 1. File count check (max 5)
CHANGED=$(git diff --cached --name-only | wc -l)
if [ "$CHANGED" -gt 5 ]; then
    echo -e "${RED}❌ BLOCKED: $CHANGED files staged (max 5).${NC}"
    echo "   Break into smaller commits. Override: git commit --no-verify"
    git diff --cached --name-only | sed 's/^/  - /'
    exit 1
fi
echo -e "${GREEN}  ✓ File count: $CHANGED / 5${NC}"

# 2. New lines warning (guideline 200)
NEW_LINES=$(git diff --cached --numstat | awk '{ a += $1 } END { print a+0 }')
if [ "$NEW_LINES" -gt 200 ]; then
    echo -e "${YELLOW}⚠️  $NEW_LINES new lines (guideline: 200). Consider splitting.${NC}"
fi
echo -e "${GREEN}  ✓ New lines: $NEW_LINES${NC}"

# 3. Go checks (only if Go files staged)
GO_FILES=$(git diff --cached --name-only -- '*.go' | wc -l)
if [ "$GO_FILES" -gt 0 ]; then
    # go vet
    echo "  Running go vet..."
    if ! go vet ./... 2>/dev/null; then
        echo -e "${RED}❌ BLOCKED: go vet failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ go vet passed${NC}"

    # go test
    echo "  Running go test..."
    if ! go test ./... -count=1 -short 2>/dev/null; then
        echo -e "${RED}❌ BLOCKED: tests failing.${NC}"
        exit 1
    fi
    echo -e "${GREEN}  ✓ tests passed${NC}"

    # Check for blank error identifiers
    for f in $(git diff --cached --name-only -- '*.go' | grep -v '_test.go'); do
        if git diff --cached -- "$f" | grep -E '^\+.*\b_\s*=' | grep -qv '//'; then
            echo -e "${YELLOW}  ⚠  Possible unhandled error in: $f${NC}"
        fi
    done

    # Check new files have corresponding test files
    for f in $(git diff --cached --diff-filter=A --name-only -- '*.go' | grep -v '_test.go'); do
        TEST="${f%.go}_test.go"
        if [ ! -f "$TEST" ]; then
            echo -e "${YELLOW}  ⚠  New file missing test: $f → $TEST${NC}"
        fi
    done
fi

echo -e "${GREEN}✅ Pre-commit checks passed.${NC}"
