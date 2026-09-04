# shellcheck shell=bash
# tests/lib/log.sh — helpers to replay and query the fake-curl recording.
# Sourced by tests/cases/*.bash after run.sh sets FAKE_CURL_LOG etc.

# Log_count: number of recorded curl invocations.
Log_count() {
    [ -f "$FAKE_CURL_LOG" ] && wc -l < "$FAKE_CURL_LOG" | tr -d ' '
    [ -f "$FAKE_CURL_LOG" ] || echo 0
}

# Log_line N — whitespace-joined argv of call N (1-based), shell-quoted words.
Log_line() {
    sed -n "${1}p" "$FAKE_CURL_LOG" 2>/dev/null | sed 's/\\//g'
}

# Log_headers N — space-joined expanded header lines of call N (1-based).
# The fake curl writes post-@file header lines to $FAKE_CURL_LOG.hdrs, one
# ---END-HDRS---terminated group per call in the same order as the argv log.
# Authorization arrives via `curl -H @file` (FIX 6), so it lives here and
# never in the argv log.
Log_headers() {
    awk -v target="$1" '
        BEGIN { RS = "---END-HDRS---\n"; n = 0 }
        { n++; if (n == target) { gsub(/^HDR /, ""); gsub(/\nHDR /, " "); gsub(/\n$/, ""); printf "%s", $0; exit } }
    ' "${FAKE_CURL_LOG}.hdrs" 2>/dev/null
}

# Log_body N — request body of call N (between ---END-CALL--- markers).
Log_body() {
    awk -v target="$1" '
        BEGIN { RS="---END-CALL---\n"; n=0 }
        { n++; if (n==target) { sub(/\n$/, ""); printf "%s", $0; exit } }
    ' "$FAKE_CURL_LOG.bodies" 2>/dev/null
}

# Log_count_bodies — number of bodies recorded (== Log_count normally).
Log_count_bodies() {
    [ -f "$FAKE_CURL_LOG.bodies" ] && grep -c '^---END-CALL---$' "$FAKE_CURL_LOG.bodies" || echo 0
}

# Url_of N — the last bare word on call N's line (the URL, per curl argv rule).
Url_of() {
    Log_line "$1" | awk '{ for (i=NF; i>0; i--) if (substr($i,1,1) != "-") { print $i; exit } }'
}

# Method_of N — method recorded after -X/--method, default GET.
Method_of() {
    local line; line="$(Log_line "$1")"
    if   printf '%s' "$line" | grep -qE '(^| )-X [A-Z]+';  then printf '%s' "$line" | grep -oE '\-X [A-Z]+' | awk '{print $2}'
    elif printf '%s' "$line" | grep -qE '(^| )--method [A-Z]+'; then printf '%s' "$line" | grep -oE '(--method [A-Z]+)' | awk '{print $2}'
    else echo GET
    fi
}

# Argv_contains N PATTERN — true if PATTERN (ERE) appears in call N's argv line.
Argv_contains() {
    printf '%s' "$(Log_line "$1")" | grep -qE -- "$2"
}

# Body_json_field N FIELD — extract a top-level FIELD value from body N via jq.
Body_json_field() {
    printf '%s' "$(Log_body "$1")" | jq -r --arg f "$2" '.[$f] // empty'
}
