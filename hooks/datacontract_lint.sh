#!/usr/bin/env bash
# PostToolUse hook: lint ODCS data contracts after Write/Edit/MultiEdit.
#
# Runs `datacontract lint` on edits to models/**/*.odcs.{yaml,yml}.
# Other paths are silently passed through.
#
# Stdin: Claude Code tool-call JSON. Exit 0 on success or non-applicable file.
# Non-zero exit + stderr surfaces the lint failure to the agent.
#
# Contracts often link business definitions (authoritativeDefinitions of type
# `semantics`) that `datacontract lint` resolves through the Entropy Data API.
# Without ENTROPY_DATA_API_KEY (and ENTROPY_DATA_HOST when the IRIs point at
# another host) those lookups fail. If those are the ONLY errors, this hook
# warns and exits 0 instead of failing; set ENTROPY_DATA_API_KEY to get the
# full check.

set -euo pipefail

# Tolerate missing jq: parse the file path with a small Python fallback.
input=$(cat)
if command -v jq >/dev/null 2>&1; then
  file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
else
  file_path=$(printf '%s' "$input" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || true)
fi

[ -n "${file_path:-}" ] || exit 0
[ -f "$file_path" ] || exit 0

# ODCS files live under models/input_ports/ or models/output_ports/v<N>/.
case "$file_path" in
  */models/input_ports/*.odcs.yaml | */models/input_ports/*.odcs.yml | \
  */models/output_ports/*/*.odcs.yaml | */models/output_ports/*/*.odcs.yml) ;;
  *) exit 0 ;;
esac

# Prefer a datacontract on PATH; fall back to the uv invocation the skills use.
if command -v datacontract >/dev/null 2>&1; then
  lint=(datacontract lint)
elif command -v uv >/dev/null 2>&1; then
  lint=(uv tool run --from 'datacontract-cli[bigquery]' datacontract lint)
else
  exit 0
fi

if out=$("${lint[@]}" "$file_path" 2>&1); then
  exit 0
fi

# The CLI ends with a numbered error summary: "1) <Check>: <details>".
errors=$(printf '%s\n' "$out" | grep -E '^[0-9]+\) ' || true)
other_errors=$(printf '%s\n' "$errors" | grep -vE '^[0-9]+\) Resolve business definition:' || true)
if [ -z "${ENTROPY_DATA_API_KEY:-}" ] && [ -n "$errors" ] && [ -z "$other_errors" ] \
   && printf '%s' "$out" | tr -s ' \n' ' ' | grep -q 'requires an API key'; then
  msg="datacontract lint: ${file_path} is valid except for semantic references (business definitions) that could not be resolved because ENTROPY_DATA_API_KEY is not set. Export ENTROPY_DATA_API_KEY (and ENTROPY_DATA_HOST if the semantics IRIs point at another Entropy Data host) to check them too."
  printf 'warning: %s\n' "$msg" >&2
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $m}}'
  fi
  exit 0
fi

printf 'datacontract lint failed for %s:\n%s\n' "$file_path" "$out" >&2
exit 1
