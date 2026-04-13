#!/usr/bin/env bash
# scripts/setup-claude-guardrails.sh
# Usage: ./scripts/setup-claude-guardrails.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Claude AI Guardrails — Team Setup${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 1. Git repo check
if [ ! -d "$REPO_ROOT/.git" ]; then
    echo -e "${RED}❌ Not a git repo. Run 'git init' first.${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Git repository${NC}"

# 2. Install hooks
echo ""
echo "Installing git hooks..."
for hook in pre-commit commit-msg; do
    SRC="$REPO_ROOT/.claude/hooks/${hook}.sh"
    DST="$REPO_ROOT/.git/hooks/${hook}"
    if [ -f "$SRC" ]; then
        cp "$SRC" "$DST" && chmod +x "$DST"
        echo -e "${GREEN}  ✓ ${hook} hook installed${NC}"
    fi
done

# 3. Verify tools
echo ""
echo "Checking tools..."
for cmd in go golangci-lint gofumpt claude; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}  ✓ ${cmd}${NC}"
    else
        echo -e "${YELLOW}  ⚠  ${cmd} not found${NC}"
    fi
done

# 4. Verify required files
echo ""
echo "Checking files..."
REQUIRED=(
    "CLAUDE.md"
    ".claude/settings.json"
    ".claude/hooks.json"
    ".claude/skills/go-error-handling.md"
    ".claude/skills/go-testing.md"
    ".claude/skills/go-interfaces.md"
    ".claude/skills/go-project-structure.md"
    ".claude/skills/go-concurrency.md"
    ".claude/skills/go-solid-patterns.md"
    ".claude/skills/go-http-handlers.md"
    ".claude/skills/go-database.md"
    ".claude/commands/pair.md"
    ".claude/commands/tdd.md"
    ".claude/commands/review.md"
    ".claude/commands/teach.md"
    ".claude/commands/scope.md"
    ".claude/commands/debug.md"
)
MISSING=0
for f in "${REQUIRED[@]}"; do
    if [ -f "$REPO_ROOT/$f" ]; then
        echo -e "${GREEN}  ✓ $f${NC}"
    else
        echo -e "${RED}  ✗ $f${NC}"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
if [ "$MISSING" -eq 0 ]; then
    echo -e "${GREEN}✅ Setup complete!${NC}"
else
    echo -e "${YELLOW}⚠️  $MISSING file(s) missing.${NC}"
fi
echo ""
echo "Quick start:"
echo "  claude          Open Claude Code"
echo "  /pair [task]    Pair programming session"
echo "  /tdd [func]     TDD cycle"
echo "  /teach [topic]  Learn a Go concept"
echo "  /scope [feat]   Break down a large task"
echo "  /review [file]  Code review"
echo "  /debug [issue]  Guided debugging"
echo ""
echo "Read docs/claude-developer-guide.md for the full walkthrough."
