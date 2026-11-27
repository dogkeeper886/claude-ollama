#!/usr/bin/env bash
# Install a repo config file, or update an installed copy and keep its values.
#
#   merge-conf.sh <repo file> <installed file>
#
# Each line of the result comes from the repo file, except a key=value line whose
# key the installed copy holds: that line keeps the copy's value. So new keys
# arrive, keys the repo dropped go, and comments follow the repo. The old copy is
# saved as <installed file>.bak.
set -euo pipefail

src="$1"
dst="$2"

if [ ! -e "$dst" ]; then
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "created $dst"
  exit 0
fi

KEY_LINE='^[[:space:]]*([^#[:space:]=]+)[[:space:]]*=(.*)$'
trim() {
  local s="${1%%#*}"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

declare -A mine=()
while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ $KEY_LINE ]] && mine["${BASH_REMATCH[1]}"]="$(trim "${BASH_REMATCH[2]}")"
done <"$dst"

declare -A kept=()
added=()
merged="$(mktemp)"
trap 'rm -f "$merged"' EXIT
while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ $KEY_LINE ]]; then
    key="${BASH_REMATCH[1]}"
    if [ -n "${mine[$key]+set}" ]; then
      printf '%s=%s\n' "$key" "${mine[$key]}"
      kept[$key]=1
      continue
    fi
    added+=("$key")
  fi
  printf '%s\n' "$line"
done <"$src" >"$merged"

dropped=()
for key in "${!mine[@]}"; do
  [ -n "${kept[$key]+set}" ] || dropped+=("$key")
done

if cmp -s "$merged" "$dst"; then
  echo "$dst is up to date"
  exit 0
fi
cp "$dst" "$dst.bak"
cat "$merged" >"$dst"
echo "updated $dst, old copy in $dst.bak"
[ ${#added[@]} -eq 0 ] || echo "  added: ${added[*]}"
[ ${#dropped[@]} -eq 0 ] || echo "  dropped: $(printf '%s\n' "${dropped[@]}" | sort | tr '\n' ' ')"
