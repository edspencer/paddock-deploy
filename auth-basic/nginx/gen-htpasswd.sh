#!/usr/bin/env bash
# Generate an htpasswd file for the nginx Basic-Auth sidecar.
#
# Usage: ./gen-htpasswd.sh <username>
#   Prompts for the password (twice) without echoing it.
#
# Output (gitignored): ./htpasswd
# Uses the `htpasswd` tool if present, otherwise falls back to `openssl passwd`
# (apr1), which nginx also understands. Neither writes the password to disk in
# plaintext or to your shell history.
set -euo pipefail

user="${1:-}"
if [ -z "$user" ]; then
	echo "Usage: $0 <username>" >&2
	exit 1
fi

dir="$(cd "$(dirname "$0")" && pwd)"
out="$dir/htpasswd"

if [ -f "$out" ]; then
	echo "Refusing to overwrite existing $out (delete it first, or edit by hand)." >&2
	exit 1
fi

read -r -s -p "Password for '$user': " pw1
echo
read -r -s -p "Repeat password: " pw2
echo
if [ "$pw1" != "$pw2" ]; then
	echo "Passwords do not match." >&2
	exit 1
fi

if command -v htpasswd >/dev/null 2>&1; then
	# -B bcrypt, -b batch (password on command line, from our variable), -c create.
	htpasswd -cbB "$out" "$user" "$pw1"
else
	echo "htpasswd not found; falling back to openssl passwd -apr1." >&2
	hash="$(openssl passwd -apr1 "$pw1")"
	printf '%s:%s\n' "$user" "$hash" >"$out"
fi

# 644 so the nginx worker (which drops to an unprivileged user) can read the
# mounted file. It contains only a password *hash*, never the plaintext.
chmod 644 "$out"
echo "Wrote $out for user '$user'."
