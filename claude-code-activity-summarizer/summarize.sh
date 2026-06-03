#!/bin/bash
# Digest new Claude Code session transcripts, summarize themes with claude -p,
# and post one Steady activity webhook per theme.
set -euo pipefail

# DRY_RUN=1: summarize the last INTERVAL_HOURS and print payloads instead of
# posting; doesn't read or write run state.
DRY_RUN="${DRY_RUN:-}"

if [ -z "$DRY_RUN" ]; then
  : "${STEADY_WEBHOOK_URL:?STEADY_WEBHOOK_URL is required}"
  : "${STEADY_EMAIL:?STEADY_EMAIL is required}"
fi

PROJECTS_DIR="${PROJECTS_DIR:-/claude-projects}"
DATA_DIR="${DATA_DIR:-/data}"
STATE_FILE="$DATA_DIR/last_run"
INTERVAL_HOURS="${INTERVAL_HOURS:-6}"
SOURCE_URL="${SOURCE_URL:-https://runsteady.com}"
PROJECT_DIRS="${PROJECT_DIRS:-}"
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-sonnet-4-6}"

mkdir -p "$DATA_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Mark the start of this run; promoted to $STATE_FILE only on success so a
# failed run gets retried over the same window.
touch "$WORK_DIR/run_started"

# Transcripts newer than the last successful run (or the last interval on
# first run; dry runs always use the interval window)
if [ -z "$DRY_RUN" ] && [ -f "$STATE_FILE" ]; then
  find_args=(-newer "$STATE_FILE")
else
  find_args=(-mmin "-$(( INTERVAL_HOURS * 60 ))")
fi

# Claude Code encodes project paths as directory names: /a/b.c -> -a-b-c
encode_path() { printf '%s' "$1" | sed 's|[^a-zA-Z0-9]|-|g'; }

allowed_projects=()
if [ -n "$PROJECT_DIRS" ]; then
  IFS=',' read -ra dirs <<< "$PROJECT_DIRS"
  for d in "${dirs[@]}"; do
    allowed_projects+=("$(encode_path "$(echo "$d" | xargs)")")
  done
fi

project_allowed() {
  [ ${#allowed_projects[@]} -eq 0 ] && return 0
  local name=$1
  for allowed in "${allowed_projects[@]}"; do
    [ "$name" = "$allowed" ] && return 0
  done
  return 1
}

# Build a per-project digest of session summaries and user prompts
DIGEST_FILE="$WORK_DIR/digest.txt"
for dir in "$PROJECTS_DIR"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  project_allowed "$name" || continue

  files=$(find "$dir" -name '*.jsonl' -type f "${find_args[@]}")
  [ -z "$files" ] && continue

  {
    echo ""
    echo "=== PROJECT: $name ==="
    echo "$files" | while read -r f; do
      jq -r '
        if .type == "summary" then "[session] \(.summary)"
        elif .type == "user" and ((.isMeta // false) | not) then
          (.message.content
            | if type == "string" then .
              elif type == "array" then ([ .[] | select(.type? == "text") | .text ] | join(" "))
              else "" end)
          | select(length > 0)
          | select(startswith("<") | not)
          | select(startswith("[Request interrupted") | not)
          | "[prompt] \(.[0:500])"
        else empty end
      ' "$f" 2>/dev/null || true
    done | head -c 100000
  } >> "$DIGEST_FILE"
done

if [ ! -s "$DIGEST_FILE" ]; then
  echo "$(date -u +%FT%TZ) no new activity"
  [ -z "$DRY_RUN" ] && mv "$WORK_DIR/run_started" "$STATE_FILE"
  exit 0
fi

PROMPT_FILE="$WORK_DIR/prompt.txt"
cat > "$PROMPT_FILE" <<'EOF'
You are summarizing work activity from Claude Code session logs for a team
activity feed. Below are digests of recent sessions grouped by project.
Project names are filesystem-encoded paths (e.g.
-Users-henrypoydar-Developer-steady-playground is ~/Developer/steady/playground).

For each project, identify the distinct themes of work. A project may have one
theme or several; closely related prompts belong to the same theme. Skip
trivial or throwaway activity.

For each theme, write one entry in this style:
"project-name — Topic area: did x, refined y, and shipped z."
where project-name is the last segment of the project path (e.g. "playground"
for -Users-henrypoydar-Developer-steady-playground). Past tense, specific, one
sentence. Each description MUST be under 230 characters total — be ruthless
about brevity.

Output ONLY a JSON array (no markdown fences, no commentary):
[{"description": "..."}]

If there is no meaningful activity, output [].

SESSION DIGESTS:
EOF
cat "$DIGEST_FILE" >> "$PROMPT_FILE"

echo "$(date -u +%FT%TZ) summarizing $(wc -c < "$DIGEST_FILE") bytes of digest"

response=$(claude -p --model "$CLAUDE_MODEL" --output-format json < "$PROMPT_FILE") \
  || { echo "claude invocation failed" >&2; exit 1; }
if [ "$(echo "$response" | jq -r '.is_error')" = "true" ]; then
  echo "claude error: $(echo "$response" | jq -r '.result')" >&2
  exit 1
fi
result=$(echo "$response" | jq -r '.result')

# Tolerate accidental code fences, then validate
summaries=$(echo "$result" | grep -v '^```' | jq -c '.')
count=$(echo "$summaries" | jq 'length')
echo "$(date -u +%FT%TZ) $count theme(s) found"

echo "$summaries" | jq -c '.[]' | while read -r item; do
  payload=$(jq -n \
    --arg email "${STEADY_EMAIL:-you@example.com}" \
    --arg url "$SOURCE_URL" \
    --arg desc "$(echo "$item" | jq -r '.description[0:256]')" \
    '{email: $email, source: "Claude Code", source_url: $url, description: $desc}')
  if [ -n "$DRY_RUN" ]; then
    echo "--- would POST:"
    echo "$payload" | jq .
  else
    curl -fsS -X POST "$STEADY_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$payload" > /dev/null < /dev/null
    echo "$(date -u +%FT%TZ) posted: $(echo "$item" | jq -r '.description' | head -c 80)"
  fi
done

[ -z "$DRY_RUN" ] && mv "$WORK_DIR/run_started" "$STATE_FILE"
exit 0
