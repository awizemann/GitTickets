#!/usr/bin/env bash
# Memophant memory hook (managed by Memophant) — regenerated; do not edit by hand.
# Surfaces this repo's memory at session start, agent-agnostic: invoked by Claude Code
# via .claude/settings.json, by Codex via .codex/hooks.json, and by Gemini CLI via
# .gemini/settings.json — the script self-locates via BASH_SOURCE, so the env-var
# fallback is only used if that fails. CLAUDE_PROJECT_DIR / CODEX_PROJECT_DIR /
# GEMINI_PROJECT_DIR are tried in order.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
[ -z "$ROOT" ] && ROOT="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${GEMINI_PROJECT_DIR:-.}}}"
echo '## Repo memory (managed by Memophant) — the single source of truth'
echo 'Use the repo memory; record durable decisions/learnings here, not in session-private memory.'
echo 'Search via the `memophant` MCP server tools (search_notes, read_note, build_context). Fallback: grep .memory/ and wiki/.'
if [ -d "$ROOT/.memory" ]; then
  echo ''
  total=$(find "$ROOT/.memory" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${total:-0}" -le 30 ]; then
    echo 'Available .memory notes:'
    find "$ROOT/.memory" -type f -name '*.md' 2>/dev/null | sed "s#^$ROOT/.memory/##" | sort | while IFS= read -r n; do echo "- $n"; done
  else
    echo "Memory: $total notes (index bounded to save context). Areas:"
    find "$ROOT/.memory" -type f -name '*.md' 2>/dev/null | sed "s#^$ROOT/.memory/##" | sed 's#/.*##' | sort | uniq -c | while read -r c d; do echo "- $d ($c)"; done
    echo 'Most recently updated:'
    git -C "$ROOT" log -n 80 --diff-filter=ACMRT --name-only --pretty=format: -- "$ROOT/.memory" 2>/dev/null | grep '\.md$' | sed 's#^.*\.memory/##' | awk 'NF && !seen[$0]++' | head -n 10 | while IFS= read -r n; do echo "- $n"; done
    echo 'Search the rest via the `memophant` MCP server (search_notes "<query>") or: find .memory -name "*.md".'
  fi
fi
if [ -d "$ROOT/wiki" ]; then
  echo ''
  echo 'Wiki present (wiki/): search the `gittickets-wiki` project via the memophant MCP server, or grep wiki/.'
fi
if [ -d "$ROOT/design" ]; then
  echo ''
  echo 'Design tier present (design/): consult before UI work — search the `gittickets-design` project via the memophant MCP server, or grep design/.'
fi
if [ -f "$ROOT/TASKS.md" ]; then
  echo ''
  echo 'Task board (TASKS.md): read it, move items to Doing/Done as you work, and add tasks you discover.'
  open_items=$(grep -c '^- \[ \]' "$ROOT/TASKS.md" 2>/dev/null)
  echo "Open checklist items: ${open_items:-0}"
fi
# MCP server status — populated by Memophant.app's health check (passive on project
# open, active via the "Recheck" button on the memory dashboard). Lets a Claude session
# know up front whether the native memophant tools are usable. When the server is down
# the fallback is grep over .memory/ and wiki/ directly — basic-memory has been retired
# from production as of 2026-06-06; see wiki/Memory-Engine-Test-Suite.md if you need to
# re-enable it for regression testing.
HEALTH_FILE="$ROOT/.memophant/mcp/health.json"
if [ -f "$HEALTH_FILE" ]; then
  echo ''
  if grep -q '"status"[[:space:]]*:[[:space:]]*"ready"' "$HEALTH_FILE" 2>/dev/null; then
    tools=$(grep -o '"tool_count"[[:space:]]*:[[:space:]]*[0-9]*' "$HEALTH_FILE" | grep -o '[0-9]*' | head -n 1)
    echo "MCP server: ✓ memophant (${tools:-?} tools)"
  else
    reason=$(grep -o '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' "$HEALTH_FILE" | sed 's/.*"\([^"]*\)"$/\1/' | head -n 1)
    echo "MCP server: ✗ memophant${reason:+ — $reason}"
    echo "  → open Memophant.app to reinstall, or grep .memory/ + wiki/ directly until the server is back."
  fi
fi
exit 0