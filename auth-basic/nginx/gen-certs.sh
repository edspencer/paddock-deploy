#!/usr/bin/env bash
# Generate a self-signed TLS certificate for the nginx Basic-Auth sidecar.
#
# Usage: ./gen-certs.sh [hostname]
#   hostname defaults to "localhost".
#
# Output (gitignored): certs/paddock.crt and certs/paddock.key.
# For a real public host, use a CA-issued cert (or switch to the Caddy variant,
# which provisions Let's Encrypt certificates automatically).
set -euo pipefail

host="${1:-localhost}"
dir="$(cd "$(dirname "$0")" && pwd)/certs"
mkdir -p "$dir"

if [ -f "$dir/paddock.crt" ] || [ -f "$dir/paddock.key" ]; then
	echo "Refusing to overwrite existing cert in $dir (delete it first)." >&2
	exit 1
fi

openssl req -x509 -newkey rsa:2048 -nodes \
	-keyout "$dir/paddock.key" \
	-out "$dir/paddock.crt" \
	-days 365 \
	-subj "/CN=$host" \
	-addext "subjectAltName=DNS:$host"

echo "Wrote $dir/paddock.crt and $dir/paddock.key (CN=$host, self-signed, 365 days)."
echo "This is self-signed: browsers will warn, and curl needs -k."
