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
#
# Each session starts from Claude Code's out-of-the-box setup in its own config
# folder, CONF_DIR/claude, so the user's ~/.claude plugins, skills and MCP servers
# stay out; load.conf then turns built-in skills, plugins, tools and features on or off.
set -euo pipefail

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-ollama"
CONFIG="$CONF_DIR/config"
LOAD_CONF="$CONF_DIR/load.conf"
# A config folder already set wins, so a caller can point a session elsewhere.
SESSION_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$CONF_DIR/claude}"

# Each setting's environment variable, and where else the setting can come from.
SETTING_KEYS=(url model context_length)
declare -A SETTING_ENV=([url]=CLAUDE_OLLAMA_URL [model]=CLAUDE_OLLAMA_MODEL [context_length]=CLAUDE_OLLAMA_CONTEXT_LENGTH)
declare -A SETTING_ALSO=([url]="" [model]=", or the first argument" [context_length]=", or --context-length")
declare -A SETTING=()

# What each feature's "off" sets; "on" leaves Claude Code's own behavior.
# auto-memory is a setting, not a variable, so launch() puts it into --settings.
declare -A FEATURE_OFF=(
  [auto-compact]="DISABLE_AUTO_COMPACT=1"
  [claude-md]="CLAUDE_CODE_DISABLE_CLAUDE_MDS=1"
  [tool-search]="ENABLE_TOOL_SEARCH=false"
  [auto-memory]=""
  [attribution-header]="CLAUDE_CODE_ATTRIBUTION_HEADER=0"
  [auto-mode-server]="CLAUDE_CODE_AUTO_MODE_SERVER=0"
  [auto-update]="DISABLE_AUTOUPDATER=1"
  [claude-ai-connectors]="ENABLE_CLAUDEAI_MCP_SERVERS=false"
  [error-reporting]="DISABLE_ERROR_REPORTING=1"
  [feedback]="DISABLE_FEEDBACK_COMMAND=1 CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1"
  [total-tokens-reminder]="CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off"
)

die() {
  printf '%s\n' "$@" >&2
  exit 1
}

# The config file is read, never sourced, so it cannot run code. Its lines take the
# shape check-conf.py enforces: blank, a "#" comment, or key=value with no spaces.
read_config() {
  [ -f "$CONFIG" ] || return 0
  local n=0 line key value
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*$ || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([a-z_]+)=(.+)$ ]] || die "$CONFIG:$n: expected key=value, with no space around '='"
    key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
    [ -n "${SETTING_ENV[$key]+known}" ] \
      || die "$CONFIG:$n: unknown key '$key' (allowed: $(printf '%s, ' "${SETTING_KEYS[@]}" | sed 's/, $//'))"
    [[ "$value" =~ ^[[:space:]]|[[:space:]]$|[[:space:]]# ]] \
      && die "$CONFIG:$n: $key's value has spaces around it or a comment after it"
    SETTING[$key]="$value"
  done <"$CONFIG"
}

read_environment() {
  local key var
  for key in "${SETTING_KEYS[@]}"; do
    var="${SETTING_ENV[$key]}"
    [ -z "${!var:-}" ] || SETTING[$key]="${!var}"
  done
}

# A first argument without a leading dash names the model; the rest go to claude.
read_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --context-length)
        [ $# -ge 2 ] || die "--context-length needs a value"
        SETTING[context_length]="$2"
        shift 2
        ;;
      --context-length=*) SETTING[context_length]="${1#*=}"; shift ;;
      *) break ;;
    esac
  done
  if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
    SETTING[model]="$1"
    shift
  fi
  CLAUDE_ARGS=("$@")
}

require_settings() {
  local key missing=()
  for key in "${SETTING_KEYS[@]}"; do
    [ -n "${SETTING[$key]:-}" ] \
      || missing+=("$(printf '  %-15s or %s%s' "$key" "${SETTING_ENV[$key]}" "${SETTING_ALSO[$key]}")")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  if [ -f "$CONFIG" ]; then
    die "claude-ollama: $CONFIG lacks these settings:" "${missing[@]}" "Add them to that file."
  fi
  die "claude-ollama: no config file at $CONFIG, so these settings are missing:" "${missing[@]}" \
    "Create the file with 'make config' in the claude-ollama repo, or copy config.example.conf there."
}

read_context_length() {
  local length="${SETTING[context_length]}"
  NUM_CTX=""
  if [[ "$length" =~ ^([0-9]+)[kK]$ ]]; then
    NUM_CTX=$((BASH_REMATCH[1] * 1024))
  elif [[ "$length" =~ ^[0-9]+$ ]]; then
    NUM_CTX=$length
  fi
  [ -n "$NUM_CTX" ] && [ "$NUM_CTX" -gt 0 ] || die "context length '$length' is not a token count like 65536 or 64k"
}

require_tools() {
  command -v claude >/dev/null || die "claude not found. Install: curl -fsSL https://claude.ai/install.sh | bash"
  local tool
  for tool in curl jq; do
    command -v "$tool" >/dev/null || die "$tool not found"
  done
}

read_load_conf() {
  [ -f "$LOAD_CONF" ] || die "claude-ollama: no load.conf at $LOAD_CONF." \
    "Create it with 'make config' in the claude-ollama repo, or copy load.conf there."
  SKILLS_OFF=() PLUGINS_OFF=() TOOLS_OFF=() FEATURE_ENV=() AUTO_MEMORY=null
  local n=0 line group name value assignments
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    [[ "$line" =~ ^(skill|plugin|tool|feature)\.([^=[:space:]]+)=(on|off)$ ]] \
      || die "$LOAD_CONF:$n: expected skill.<name>, plugin.<name>, tool.<name> or feature.<name>, set to on or off"
    group="${BASH_REMATCH[1]}" name="${BASH_REMATCH[2]}" value="${BASH_REMATCH[3]}"
    case "$group" in
      skill) [ "$value" = on ] || SKILLS_OFF+=("$name") ;;
      plugin) [ "$value" = on ] || PLUGINS_OFF+=("$name") ;;
      tool) [ "$value" = on ] || TOOLS_OFF+=("$name") ;;
      feature)
        [ -n "${FEATURE_OFF[$name]+known}" ] || die "$LOAD_CONF:$n: unknown feature '$name' (known: ${!FEATURE_OFF[*]})"
        if [ "$name" = auto-memory ]; then
          AUTO_MEMORY=$([ "$value" = on ] && echo true || echo false)
        elif [ "$value" = off ]; then
          read -r -a assignments <<<"${FEATURE_OFF[$name]}"
          FEATURE_ENV+=("${assignments[@]}")
        fi
        ;;
    esac
  done <"$LOAD_CONF"
}

# The Ollama server's API, and the fields of its replies.
ollama_up() { curl -sf "$URL/api/version" >/dev/null; }
ollama_show() { curl -s "$URL/api/show" -d "$(jq -nc --arg m "$1" '{model: $m}')"; }
ollama_models() { curl -s "$URL/api/tags" | jq -r '.models[].name'; }
ollama_create() {
  curl -s "$URL/api/create" -d "$(jq -nc --arg m "$1" --arg f "$2" --argjson n "$3" \
    '{model: $m, from: $f, parameters: {num_ctx: $n}, stream: false}')"
}
reply_error() { jq -r '.error // empty'; }
reply_capabilities() { jq -r '.capabilities // [] | join(",")'; }
reply_has_tools() { jq -e '.capabilities // [] | index("tools")' >/dev/null 2>&1; }
reply_num_ctx() { jq -r '.parameters // ""' | awk '$1 == "num_ctx" { print $2 }'; }
reply_ok() { jq -e '.status == "success"' >/dev/null; }

check_model() {
  ollama_up || die "no Ollama server at $URL"
  local base_info error model listing=()
  base_info=$(ollama_show "$MODEL")
  error=$(reply_error <<<"$base_info")
  [ -z "$error" ] || die "$MODEL is not on $URL ($error). Pull it: ollama pull $MODEL"
  # Claude Code sends tool definitions on every request; the server refuses them for
  # a model without the tools capability.
  reply_has_tools <<<"$base_info" && return 0
  for model in $(ollama_models); do
    ollama_show "$model" | reply_has_tools && listing+=("  $model")
  done
  die "$MODEL does not support tools (capabilities: $(reply_capabilities <<<"$base_info")); Claude Code needs it" \
    "tools-capable models on $URL:" "${listing[@]}"
}

ensure_copy() {
  if [ $((NUM_CTX % 1024)) -eq 0 ]; then
    COPY_MODEL="$MODEL-$((NUM_CTX / 1024))k"
  else
    COPY_MODEL="$MODEL-ctx$NUM_CTX"
  fi
  local copy_num_ctx create_response
  copy_num_ctx=$(ollama_show "$COPY_MODEL" | reply_num_ctx)
  [ "$copy_num_ctx" = "$NUM_CTX" ] && return 0
  echo "creating $COPY_MODEL from $MODEL with num_ctx $NUM_CTX" >&2
  create_response=$(ollama_create "$COPY_MODEL" "$MODEL" "$NUM_CTX")
  reply_ok <<<"$create_response" || die "could not create $COPY_MODEL: $create_response"
}

# A JSON object that maps each name to one JSON value: json_map '"off"' a b gives {"a":"off","b":"off"}.
json_map() {
  local value="$1"
  shift
  printf '%s\n' "$@" | jq -Rn --argjson v "$value" '[inputs | select(length > 0) | {(.): $v}] | add // {}'
}

launch() {
  echo "claude -> $URL ($COPY_MODEL, $NUM_CTX tokens)" >&2
  export ANTHROPIC_BASE_URL="$URL"
  export ANTHROPIC_AUTH_TOKEN=ollama
  # Empty, not unset: a key in the environment wins over the base URL and the
  # session would go to Anthropic instead.
  export ANTHROPIC_API_KEY=""
  export CLAUDE_CONFIG_DIR="$SESSION_CONFIG_DIR"
  # Every model tier and every subagent runs on the copy: Ollama has no Claude model names.
  export ANTHROPIC_MODEL="$COPY_MODEL"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$COPY_MODEL"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$COPY_MODEL"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$COPY_MODEL"
  export CLAUDE_CODE_SUBAGENT_MODEL="$COPY_MODEL"
  # Claude Code assumes a 1M-token window for a model ID it doesn't recognize, and
  # compacts to fit that window; give it the copy's real one.
  export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$NUM_CTX"
  # Keep the session on Ollama even when Claude Code settings name another provider or endpoint.
  export CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=1
  export CLAUDE_CODE_USE_BEDROCK= CLAUDE_CODE_USE_VERTEX= CLAUDE_CODE_USE_FOUNDRY=
  export CLAUDE_CODE_USE_ANTHROPIC_AWS= CLAUDE_CODE_USE_ANTHROPIC_GOOGLE_CLOUD=
  export CLAUDE_CODE_USE_MANTLE= CLAUDE_CODE_USE_GATEWAY=
  local assignment
  for assignment in "${FEATURE_ENV[@]}"; do
    export "${assignment?}"
  done
  # Session-only settings: they shape this session and write nothing to disk.
  local settings
  settings=$(jq -nc \
    --argjson skills "$(json_map '"off"' "${SKILLS_OFF[@]}")" \
    --argjson plugins "$(json_map false "${PLUGINS_OFF[@]}")" \
    --argjson memory "$AUTO_MEMORY" \
    '{skillOverrides: $skills, enabledPlugins: $plugins, autoMemoryEnabled: $memory} | with_entries(select(.value != null))')
  # --disallowed-tools takes every following word up to the next option, so it goes
  # before --settings, where it cannot swallow the user's own arguments.
  local disallowed=()
  [ ${#TOOLS_OFF[@]} -eq 0 ] || disallowed=(--disallowed-tools "${TOOLS_OFF[@]}")
  exec claude --model "$COPY_MODEL" "${disallowed[@]}" --settings "$settings" "${CLAUDE_ARGS[@]}"
}

read_config
read_environment
read_arguments "$@"
require_settings
URL="${SETTING[url]%/}"
MODEL="${SETTING[model]}"
read_context_length
require_tools
read_load_conf
check_model
ensure_copy
launch
