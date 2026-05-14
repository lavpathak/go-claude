#!/usr/bin/env bash
# .claude/hooks/commit-msg.sh
# Install: cp .claude/hooks/commit-msg.sh .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg

set -euo pipefail

MSG_FILE="$1"
FIRST_LINE=$(head -n1 "$MSG_FILE")
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

# Claude-assisted commits must carry the Co-authored-by trailer.
# Skip merge / fixup / revert commits — those aren't authored content.
if echo "$FIRST_LINE" | grep -Eq '^(Merge|fixup!|squash!|Revert)'; then
    echo "✓ Commit message valid (trailer check skipped for $FIRST_LINE)"
    exit 0
fi

if ! grep -Eqi '^Co-authored-by:[[:space:]]+Claude[[:space:]]+<claude@anthropic\.com>' "$MSG_FILE"; then
    echo "❌ Missing Claude attribution trailer."
    echo ""
    echo "   Per CLAUDE.md, Claude-assisted commits must include:"
    echo "     Co-authored-by: Claude <claude@anthropic.com>"
    echo ""
    echo "   If this commit was NOT Claude-assisted, bypass with: git commit --no-verify"
    exit 1
fi

echo "✓ Commit message valid"
