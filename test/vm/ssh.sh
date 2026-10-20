# The ssh options for the lab VM, shared by lib.sh, deploy.sh and install-package.sh. Source it from test/vm/.
# One connection is reused for every call (ControlMaster): a suite makes hundreds of calls, and a fresh ssh handshake
# each time was a large part of its run. The keepalives notice a master whose VM went away.
SSHO=(-i "$(dirname "${BASH_SOURCE[0]}")/keys/id_oi" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o BatchMode=yes -o LogLevel=ERROR -o ConnectTimeout=8
  -o ControlMaster=auto -o "ControlPath=${XDG_RUNTIME_DIR:-/tmp}/oi-lab-%C" -o ControlPersist=120
  -o ServerAliveInterval=5 -o ServerAliveCountMax=3)
