#!/usr/bin/env bash
set -euo pipefail

# Run from a machine with Docker and OpenSSL. Each run gets a private network.
image=${1:-debian:12-slim}
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
run=nginx-proxy-${tmp##*.}
network=$run
pebble=$run-acme
cleanup() {
    docker rm -f "$pebble" >/dev/null 2>&1 || :
    docker network rm "$network" >/dev/null 2>&1 || :
    rm -rf -- "$tmp"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=pebble \
    -addext subjectAltName=DNS:pebble -keyout "$tmp/acme.key" -out "$tmp/acme.crt" 2>/dev/null
mkdir -p "$tmp/repo/tests"
cp "$repo/install.sh" "$repo/nginx-reverse-proxy" "$tmp/repo/"
cp "$repo/tests/smoke-inside.sh" "$tmp/repo/tests/"
chmod 755 "$tmp"
chmod 644 "$tmp/acme.key"
cat >"$tmp/pebble.json" <<'PEBBLE'
{"pebble":{"listenAddress":"0.0.0.0:14000","managementListenAddress":"0.0.0.0:15000","certificate":"/fixtures/acme.crt","privateKey":"/fixtures/acme.key","httpPort":80,"tlsPort":443}}
PEBBLE

docker network create "$network" >/dev/null
docker run -d --name "$pebble" --network "$network" --network-alias pebble \
    --mount "type=bind,src=$tmp,dst=/fixtures,readonly" -e PEBBLE_VA_NOSLEEP=1 \
    ghcr.io/letsencrypt/pebble@sha256:0c81f05db371f436c97fb894bd6d2ab8fc9c8e2ce40f8bef8a8e15941bcd75ef \
    -config /fixtures/pebble.json -dnsserver 127.0.0.11:53 >/dev/null

if docker run --rm --network "$network" \
    --network-alias site.test --network-alias www.site.test \
    --network-alias secure.test --network-alias bad.test \
    --mount "type=bind,src=$tmp/repo,dst=/repo,readonly" \
    --mount "type=bind,src=$tmp,dst=/fixtures,readonly" \
    "$image" bash /repo/tests/smoke-inside.sh; then
    echo "Smoke test passed on $image."
else
    docker logs "$pebble" >&2
    exit 1
fi
