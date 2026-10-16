#!/bin/bash
# trylogin.sh <user> <password>: password SSH login to the VM through the real PAM stack.
set -u
H="$(cd "$(dirname "$0")" && pwd)"
A=$(mktemp); printf '#!/bin/sh\necho "%s"\n' "$2" > "$A"; chmod +x "$A"
SSH_ASKPASS="$A" SSH_ASKPASS_REQUIRE=force setsid -w ssh -o PreferredAuthentications=password,keyboard-interactive \
  -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o NumberOfPasswordPrompts=1 -p 2222 "$1@127.0.0.1" 'echo "LOGIN-OK uid=$(id -u) user=$(id -un) home=$HOME"' 2>&1 | tail -2; echo "exit=${PIPESTATUS[0]}"
rm -f "$A"
