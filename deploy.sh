#!/usr/bin/env bash
set -euo pipefail

# ---- infra config: edit these 3 ----
PROJECT_ID="n8n-local-466315"
ZONE="us-central1-c"
INSTANCE="free-ec2-micro"
# ------------------------------------

IMAGE_REPO="javidjamae/discord-gateway-bot"
TAG="${TAG:-latest}"                       # or set TAG=$(git rev-parse --short HEAD)
IMAGE="${IMAGE_REPO}:${TAG}"

if [[ ! -f .env ]]; then
  echo "Missing .env at repo root. Create it from .env.example"
  exit 1
fi
if [[ ! -f startup.sh ]]; then
  echo "Missing startup.sh at repo root"
  exit 1
fi

echo "Building ${IMAGE}..."
docker build -t "${IMAGE}" .

echo "Pushing ${IMAGE}..."
docker push "${IMAGE}"

echo "Pushing env vars from .env to instance metadata..."
# Pull only the vars the startup script expects
DISCORD_TOKEN=$(grep -E '^DISCORD_TOKEN=' .env | cut -d= -f2-)
APPLICATION_ID=$(grep -E '^APPLICATION_ID=' .env | cut -d= -f2-)
GUILD_ID=$(grep -E '^GUILD_ID=' .env | cut -d= -f2-)
N8N_WEBHOOK_URL=$(grep -E '^N8N_WEBHOOK_URL=' .env | cut -d= -f2-)

gcloud config set project "${PROJECT_ID}" >/dev/null

gcloud compute instances add-metadata "${INSTANCE}" \
  --zone "${ZONE}" \
  --metadata \
DISCORD_TOKEN="${DISCORD_TOKEN}",\
APPLICATION_ID="${APPLICATION_ID}",\
GUILD_ID="${GUILD_ID}",\
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL}"

echo "Attaching startup script..."
gcloud compute instances add-metadata "${INSTANCE}" \
  --zone "${ZONE}" \
  --metadata-from-file startup-script=./startup.sh

echo "Rebooting instance to apply..."
gcloud compute instances stop "${INSTANCE}" --zone "${ZONE}" --quiet
gcloud compute instances start "${INSTANCE}" --zone "${ZONE}" --quiet

echo "Deployed ${IMAGE}. Check boot logs next."
echo "To view logs:"
echo "  gcloud compute instances get-serial-port-output ${INSTANCE} --zone ${ZONE} --port 1 | tail -n 200"
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# deploy.sh
# Builds and pushes the Docker image, then updates a GCE VM's metadata and
# startup script so the VM pulls the new image and runs it. No secrets are printed.
# Configuration comes from environment variables or a local .env file (not committed).
# ------------------------------------------------------------------------------

# Load local .env if present (exports all keys)
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

# ---- Non-secret infra config (must be provided via env/.env) ------------------
: "${GCP_PROJECT:?Set GCP_PROJECT in .env or your shell}"
: "${GCP_ZONE:?Set GCP_ZONE in .env or your shell}"
: "${INSTANCE_NAME:=free-ec2-micro}"

# Image coordinates (can be overridden)
: "${IMAGE_REPO:=javidjamae/discord-gateway-bot}"
: "${TAG:=latest}"   # or set TAG=$(git rev-parse --short HEAD) before running
IMAGE="${IMAGE_REPO}:${TAG}"

# ---- Required app secrets (must be in .env or exported) -----------------------
: "${DISCORD_TOKEN:?Set DISCORD_TOKEN in .env or your shell}"
: "${APPLICATION_ID:?Set APPLICATION_ID in .env or your shell}"
: "${GUILD_ID:?Set GUILD_ID in .env or your shell}"
: "${N8N_WEBHOOK_URL:?Set N8N_WEBHOOK_URL in .env or your shell}"

# ---- Validations --------------------------------------------------------------
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud CLI not found. Install it and authenticate before deploying." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. Install Docker Desktop/Engine before deploying." >&2
  exit 1
fi

if [[ ! -f startup.sh ]]; then
  echo "Missing startup.sh at repo root" >&2
  exit 1
fi

# ---- Build & push image -------------------------------------------------------
echo "Building ${IMAGE}…"
docker build -t "${IMAGE}" .

echo "Pushing ${IMAGE}…"
docker push "${IMAGE}"

# ---- Configure instance metadata safely --------------------------------------
echo "Configuring project ${GCP_PROJECT}…"
gcloud config set project "${GCP_PROJECT}" >/dev/null

echo "Updating instance metadata on ${INSTANCE_NAME} (${GCP_ZONE})…"
# Do NOT echo secret values. We just pass them to gcloud.
gcloud compute instances add-metadata "${INSTANCE_NAME}" \
  --zone "${GCP_ZONE}" \
  --metadata \
DISCORD_TOKEN="${DISCORD_TOKEN}",\
APPLICATION_ID="${APPLICATION_ID}",\
GUILD_ID="${GUILD_ID}",\
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL}",\
DOCKER_IMAGE="${IMAGE}"

echo "Attaching startup script…"
gcloud compute instances add-metadata "${INSTANCE_NAME}" \
  --zone "${GCP_ZONE}" \
  --metadata-from-file startup-script=./startup.sh

# ---- Restart to apply ---------------------------------------------------------
echo "Rebooting instance to apply…"
gcloud compute instances stop "${INSTANCE_NAME}" --zone "${GCP_ZONE}" --quiet
gcloud compute instances start "${INSTANCE_NAME}" --zone "${GCP_ZONE}" --quiet

# ---- Helpful output -----------------------------------------------------------
INTERNAL_IP=$(gcloud compute instances describe "${INSTANCE_NAME}" --zone "${GCP_ZONE}" --format='get(networkInterfaces[0].networkIP)' || true)
EXTERNAL_IP=$(gcloud compute instances describe "${INSTANCE_NAME}" --zone "${GCP_ZONE}" --format='get(networkInterfaces[0].accessConfigs[0].natIP)' || true)

echo "Deployed ${IMAGE}."
[[ -n "${INTERNAL_IP}" ]] && echo "Instance internal IP: ${INTERNAL_IP}"
[[ -n "${EXTERNAL_IP}" ]] && echo "Instance external IP: ${EXTERNAL_IP}"
echo "Tail boot logs with:"
echo "  gcloud compute instances get-serial-port-output ${INSTANCE_NAME} --zone ${GCP_ZONE} --port 1 | tail -n 200"