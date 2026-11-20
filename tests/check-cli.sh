#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash install.sh --help | grep -F 'install.sh' >/dev/null
bash nginx-reverse-proxy --help | grep -F 'add --file' >/dev/null

if result=$(bash nginx-reverse-proxy bogus 2>&1); then
    echo 'An unknown command was accepted.' >&2
    exit 1
fi
grep -Fq 'Unknown command: bogus' <<<"$result"
