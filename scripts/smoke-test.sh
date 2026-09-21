#!/bin/sh
# End-to-end check that the "ollama web" engine is installed and answering.
#
# Usage:
#   ./scripts/smoke-test.sh [BASE_URL]
#
# BASE_URL defaults to http://localhost:8080. Requires curl and jq.

set -eu

BASE_URL="${1:-http://localhost:8080}"
QUERY="${QUERY:-ollama web search api}"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

echo "==> checking ${BASE_URL} is reachable"
curl -sS -o /dev/null -m 20 "${BASE_URL}/" || fail "cannot reach ${BASE_URL}"

echo "==> checking the 'ollama web' engine is registered"
registered=$(curl -sS -m 20 "${BASE_URL}/config" \
    | jq -r '[.engines[] | select(.name == "ollama web")] | length')
[ "$registered" -eq 1 ] || fail "engine 'ollama web' is not registered"
echo "    registered, shortcut: $(curl -sS -m 20 "${BASE_URL}/config" \
    | jq -r '.engines[] | select(.name == "ollama web") | .shortcut')"

echo "==> querying the engine directly (engine-specific)"
# The API intermittently returns an empty result set on the first attempt, so
# give the engine a few tries before declaring it broken. A response we cannot
# parse, and one that names the engine in unresponsive_engines, are not
# transient: those break out immediately so the checks below report them.
ATTEMPTS="${ATTEMPTS:-3}"
attempt=0
while :; do
    attempt=$((attempt + 1))
    resp=$(curl -sS -m 60 --get "${BASE_URL}/search" \
        --data-urlencode "q=${QUERY}" \
        --data 'format=json' \
        --data-urlencode 'engines=ollama web')

    # printf, not echo: dash (Debian/Ubuntu /bin/sh) expands backslash escapes
    # in echo, which corrupts the JSON before jq ever sees it.
    #
    # `|| true` plus the ${n:-0} default: under `set -e` a non-JSON body (a
    # gateway error page served with HTTP 200, say) makes jq exit non-zero and
    # would abort the whole test here with a bare parse error; a valid but
    # empty body prints nothing, leaving n empty and breaking -gt. Both are
    # normalized to 0 so the loop and the checks below stay meaningful.
    n=$(printf '%s' "$resp" | jq -r '.results | length' 2>/dev/null || true)
    n=${n:-0}
    [ "$n" -gt 0 ] && break
    # A hard engine error (bad OLLAMA_API_KEY, suspension) will not resolve
    # itself; let the unresponsive check below print the real diagnostic
    # rather than sleeping through every attempt.
    printf '%s' "$resp" \
        | jq -e '[.unresponsive_engines // [] | .[] | select(.[0] == "ollama web")] | length == 0' \
            >/dev/null 2>&1 || break
    [ "$attempt" -lt "$ATTEMPTS" ] || break
    echo "    no results on attempt ${attempt}/${ATTEMPTS}; retrying" >&2
    sleep 2
done

unresp=$(printf '%s' "$resp" | jq -r '[.unresponsive_engines // [] | .[] | select(.[0] == "ollama web")] | length' 2>/dev/null || true)
unresp=${unresp:-0}

if [ "$unresp" -ne 0 ]; then
    printf '%s' "$resp" | jq -r '.unresponsive_engines'
    fail "the engine reported an error (check your OLLAMA_API_KEY)"
fi
[ "$n" -gt 0 ] || fail "the engine returned zero results"
echo "    ${n} results"

echo "==> sample result"
# The API sometimes returns an entry with an empty title, so show the first
# result that actually has one.
printf '%s' "$resp" | jq -r '[.results[] | select(.title != "")][0] | "    \(.title)\n    \(.url)"'

echo "==> querying the default engine set (mixed search)"
mixed=$(curl -sS -m 60 --get "${BASE_URL}/search" \
    --data-urlencode "q=${QUERY}" \
    --data 'format=json')
printf '%s' "$mixed" | jq -r '"    \(.results | length) results from: \([.results[].engine] | unique | join(", "))"'

echo
echo "OK: 'ollama web' is installed and returning results."
