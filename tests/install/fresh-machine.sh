#!/usr/bin/env bash
# Opt-in: clean Linux container, real Claude Code CLI, install.sh run twice. Needs Docker and network.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
docker run --rm -v "$REPO:/src:ro" ubuntu:24.04 bash -c '
  set -e
  apt-get update -qq && apt-get install -y -qq curl git jq ca-certificates >/dev/null
  curl -fsSL https://claude.ai/install.sh | bash >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
  cp -R /src "/root/claude setup"
  "/root/claude setup/install.sh"
  "/root/claude setup/install.sh" | tee /tmp/run2
  grep -q "Summary: 0 changed" /tmp/run2
  claude plugin list | grep -q podium@claude-setup
  echo FRESH_OK
'
