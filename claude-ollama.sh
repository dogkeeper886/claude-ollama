#!/usr/bin/env bash
# Launch Claude Code against an Ollama server, on a chosen model and context length.
#
#   claude-ollama [--context-length N] [model] [claude args...]
#   claude-ollama -p "explain this repo"
#   claude-ollama --context-length 32k qwen3.8:27b
#
# Settings, highest first: the command line; CLAUDE_OLLAMA_URL, CLAUDE_OLLAMA_MODEL
# and CLAUDE_OLLAMA_CONTEXT_LENGTH; the config file. There are no built-in
# defaults: a setting none of them gives stops the launch with its name.
#
# The Anthropic API that Claude Code speaks has no context-length field, so the
# length rides on a model copy, <model>-64k: made once through /api/create with
# num_ctx, reused after. A model's own num_ctx wins over the server default.
set -euo pipefail

URL=""
MODEL=""
CONTEXT_LENGTH=""

# The config file is read as key=value lines, never sourced, so it cannot run code.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-ollama/config"
if [ -f "$CONFIG" ]; then
  n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="${line%%#*}"
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    if [[ ! "$line" =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]]; then
      echo "$CONFIG:$n: expected key=value" >&2
      exit 1
    fi
    case "${BASH_REMATCH[1]}" in
      url) URL="${BASH_REMATCH[2]}" ;;
      model) MODEL="${BASH_REMATCH[2]}" ;;
      context_length) CONTEXT_LENGTH="${BASH_REMATCH[2]}" ;;
      *)
        echo "$CONFIG:$n: unknown key '${BASH_REMATCH[1]}' (allowed: url, model, context_length)" >&2
        exit 1
        ;;
    esac
  done <"$CONFIG"
fi

URL="${CLAUDE_OLLAMA_URL:-$URL}"
MODEL="${CLAUDE_OLLAMA_MODEL:-$MODEL}"
CONTEXT_LENGTH="${CLAUDE_OLLAMA_CONTEXT_LENGTH:-$CONTEXT_LENGTH}"

while [ $# -gt 0 ]; do
  case "$1" in
    --context-length)
      [ $# -ge 2 ] || { echo "--context-length needs a value" >&2; exit 1; }
      CONTEXT_LENGTH="$2"
      shift 2
      ;;
    --context-length=*) CONTEXT_LENGTH="${1#*=}"; shift ;;
    *) break ;;
  esac
done
# A first argument without a leading dash names the model; the rest go to claude.
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  MODEL="$1"
  shift
fi

missing=()
[ -n "$URL" ] || missing+=("  url             or CLAUDE_OLLAMA_URL")
[ -n "$MODEL" ] || missing+=("  model           or CLAUDE_OLLAMA_MODEL, or the first argument")
[ -n "$CONTEXT_LENGTH" ] || missing+=("  context_length  or CLAUDE_OLLAMA_CONTEXT_LENGTH, or --context-length")
if [ ${#missing[@]} -gt 0 ]; then
  if [ -f "$CONFIG" ]; then
    echo "claude-ollama: $CONFIG lacks these settings:" >&2
    printf '%s\n' "${missing[@]}" >&2
    echo "Add them to that file." >&2
  else
    echo "claude-ollama: no config file at $CONFIG, so these settings are missing:" >&2
    printf '%s\n' "${missing[@]}" >&2
    echo "Create the file with 'make config' in the claude-ollama repo, or copy config.example.conf there." >&2
  fi
  exit 1
fi
URL="${URL%/}"

NUM_CTX=""
if [[ "$CONTEXT_LENGTH" =~ ^([0-9]+)[kK]$ ]]; then
  NUM_CTX=$((BASH_REMATCH[1] * 1024))
elif [[ "$CONTEXT_LENGTH" =~ ^[0-9]+$ ]]; then
  NUM_CTX=$CONTEXT_LENGTH
fi
if [ -z "$NUM_CTX" ] || [ "$NUM_CTX" -le 0 ]; then
  echo "context length '$CONTEXT_LENGTH' is not a token count like 65536 or 64k" >&2
  exit 1
fi

command -v claude >/dev/null || {
  echo "claude not found. Install: curl -fsSL https://claude.ai/install.sh | bash" >&2
  exit 1
}
for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool not found" >&2; exit 1; }
done

curl -sf "$URL/api/version" >/dev/null || {
  echo "no Ollama server at $URL" >&2
  exit 1
}

show() {
  curl -s "$URL/api/show" -d "$(jq -nc --arg m "$1" '{model: $m}')"
}

base=$(show "$MODEL")
if jq -e '.error' <<<"$base" >/dev/null; then
  echo "$MODEL is not on $URL ($(jq -r '.error' <<<"$base")). Pull it: ollama pull $MODEL" >&2
  exit 1
fi
# Claude Code sends tool definitions on every request; the server refuses them for
# a model without the tools capability.
if ! jq -e '.capabilities // [] | index("tools")' <<<"$base" >/dev/null; then
  echo "$MODEL does not support tools (capabilities: $(jq -r '.capabilities // [] | join(",")' <<<"$base")); Claude Code needs it" >&2
  echo "tools-capable models on $URL:" >&2
  for m in $(curl -s "$URL/api/tags" | jq -r '.models[].name'); do
    show "$m" | jq -e '.capabilities // [] | index("tools")' >/dev/null 2>&1 && echo "  $m" >&2
  done
  exit 1
fi

if [ $((NUM_CTX % 1024)) -eq 0 ]; then
  RUN_MODEL="$MODEL-$((NUM_CTX / 1024))k"
else
  RUN_MODEL="$MODEL-ctx$NUM_CTX"
fi
have=$(show "$RUN_MODEL" | jq -r '.parameters // ""' | awk '$1 == "num_ctx" { print $2 }')
if [ "$have" != "$NUM_CTX" ]; then
  echo "creating $RUN_MODEL from $MODEL with num_ctx $NUM_CTX" >&2
  created=$(curl -s "$URL/api/create" -d "$(jq -nc --arg m "$RUN_MODEL" --arg f "$MODEL" --argjson n "$NUM_CTX" \
    '{model: $m, from: $f, parameters: {num_ctx: $n}, stream: false}')")
  jq -e '.status == "success"' <<<"$created" >/dev/null || {
    echo "could not create $RUN_MODEL: $created" >&2
    exit 1
  }
fi

echo "claude -> $URL ($RUN_MODEL, $NUM_CTX tokens)" >&2

export ANTHROPIC_BASE_URL="$URL"
export ANTHROPIC_AUTH_TOKEN=ollama
# Empty, not unset: a key in the environment wins over the base URL and the
# session would go to Anthropic instead.
export ANTHROPIC_API_KEY=""
export DISABLE_AUTOUPDATER=1
# Every model tier and every subagent runs on the copy: Ollama has no Claude model names.
export ANTHROPIC_MODEL="$RUN_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$RUN_MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$RUN_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$RUN_MODEL"
export CLAUDE_CODE_SUBAGENT_MODEL="$RUN_MODEL"
# Claude Code assumes a 1M-token window for a model ID it doesn't recognize, and
# compacts to fit that window; give it the copy's real one.
export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$NUM_CTX"
# From upstream's `ollama launch claude`: keep the session on Ollama even when
# Claude Code settings name another provider or endpoint.
export CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1
export CLAUDE_CODE_USE_BEDROCK= CLAUDE_CODE_USE_VERTEX= CLAUDE_CODE_USE_FOUNDRY=
export CLAUDE_CODE_USE_ANTHROPIC_AWS= CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD=
export CLAUDE_CODE_USE_MANTLE= CLAUDE_CODE_USE_GATEWAY=
# Also from upstream: turn off what needs Anthropic's servers.
export ENABLE_CLAUDEAI_MCP_SERVERS=false
export CLAUDE_CODE_ATTRIBUTION_HEADER=0
export CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off
export DISABLE_ERROR_REPORTING=1
export DISABLE_FEEDBACK_COMMAND=1
export CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1
export CLAUDE_CODE_AUTO_MODE_SERVER="${CLAUDE_CODE_AUTO_MODE_SERVER-0}"

exec claude --model "$RUN_MODEL" "$@"
