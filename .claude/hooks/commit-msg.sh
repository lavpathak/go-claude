#!/usr/bin/env bash
# .claude/hooks/commit-msg.sh
# Install: cp .claude/hooks/commit-msg.sh .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg

set -euo pipefail

FIRST_LINE=$(head -n1 "$1")
PATTERN="^(feat|fix|test|refactor|docs|chore|build|ci|perf|style)\(.*\): .{10,}"

if ! echo "$FIRST_LINE" | grep -Eq "$PATTERN"; then
    echo "❌ Invalid commit message format."
    echo ""
    echo "   Required: type(scope): description (10+ chars)"
    echo "   Types:    feat fix test refactor docs chore build ci perf style"
    echo "   Example:  feat(auth): add JWT token expiry validation"
    echo ""
    echo "   Got: $FIRST_LINE"
    exit 1
fi

echo "✓ Commit message valid"
