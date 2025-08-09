#!/usr/bin/env bash
set -euo pipefail

log() { echo "[startup] $*"; }
meta() {
  curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1"
}

# 1) Install Docker if missing
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
  log "Docker installed."
fi

# 2) Materialize env file from instance metadata (do not echo secrets)
log "Writing env file..."
install -d -m 755 /opt/discord-bot
cat >/opt/discord-bot/.env <<EOF
DISCORD_TOKEN=$(meta DISCORD_TOKEN)
APPLICATION_ID=$(meta APPLICATION_ID)
GUILD_ID=$(meta GUILD_ID)
N8N_WEBHOOK_URL=$(meta N8N_WEBHOOK_URL)
EOF
chmod 600 /opt/discord-bot/.env

# 3) Resolve image from metadata or fall back to default
IMAGE="$(meta DOCKER_IMAGE || true)"
if [[ -z "${IMAGE}" ]]; then
  IMAGE="javidjamae/discord-gateway-bot:latest"
fi

# 4) Run or restart the container
CONTAINER_NAME="discord-gateway-bot"
log "Launching container ${IMAGE}..."
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
docker pull "${IMAGE}" || true
docker run -d --name "${CONTAINER_NAME}" \
  --restart=always \
  --env-file /opt/discord-bot/.env \
  "${IMAGE}"

log "Done."