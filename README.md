# Discord Bot Example

A Discord **slash‑command gateway** that forwards requests to an n8n workflow (hosted on n8n Cloud or self‑hosted). It runs as a tiny Node.js service in Docker and is deployable to any VPS. This repo also includes a GCP one‑command deploy using instance metadata + a startup script.

---

## How it works

1. A user runs a slash command in Discord (e.g. `/generate-ideas`).
2. This bot receives the interaction via the Discord Gateway and validates it.
3. The bot forwards the payload to your **n8n webhook**.
4. n8n runs your workflow and the bot relays the result back to Discord.

---

## Repo layout

```
.
├── Dockerfile
├── docker-compose.yml             # local run convenience (uses .env)
├── index.js                       # discord gateway → n8n webhook
├── package.json
├── package-lock.json
├── startup.sh                     # VM startup script (installs Docker + runs image)
├── deploy.sh                      # one‑command GCP deploy using instance metadata
├── .env.example                   # copy → .env and fill in secrets (never commit .env)
└── README.md
```

> **Never commit your real `.env`**. Only commit `.env.example`.

---

## Quick start (local)

Requirements: Docker Desktop (or docker + compose), a Discord Application with a Bot token, an n8n webhook.

```bash
cp .env.example .env
# edit .env and set your values (token, IDs, n8n URL)

# build & run locally
docker compose up --build
```

The bot will start and connect to Discord. Use `CTRL+C` to stop.

---

## Environment variables

These are loaded from `.env` for local/dev and are pushed into GCP instance metadata by `deploy.sh` for remote deploys.

```ini
# Discord & n8n
DISCORD_TOKEN=your_bot_secret_token
APPLICATION_ID=your_bot_client_id
GUILD_ID=your_discord_server_id
N8N_WEBHOOK_URL=https://YOUR-SUBDOMAIN.app.n8n.cloud/webhook/discord-slash

# Deployment (optional; used by deploy.sh)
GCP_PROJECT=your_gcp_project_id
GCP_ZONE=us-central1-c
INSTANCE_NAME=free-ec2-micro
IMAGE_REPO=javidjamae/discord-gateway-bot
```

> `DISCORD_TOKEN` is a **secret** and must never be committed.

---

## Register slash commands

Use the helper built into `index.js`:

```bash
# ensure env vars are set; sourcing .env is one option
source .env
npm run register
```

The script reads `DISCORD_TOKEN`, `APPLICATION_ID`, and optionally `GUILD_ID` from the environment. If `GUILD_ID` is set, the commands register for that guild instantly; otherwise they register globally and may take up to an hour to appear.

Whenever you change the command definitions in `index.js`, run `npm run register` again to push the updates to Discord.

---

## One‑command deploy to an existing GCP VM

This keeps everything **version controlled** and avoids SSHing into the instance.

Prereqs:
- gcloud CLI installed & authenticated
- An existing Debian/Ubuntu VM with an external IP
- `GCP_PROJECT`, `GCP_ZONE`, `INSTANCE_NAME`, and `IMAGE_REPO` set in `.env`

Deploy:

```bash
./deploy.sh
```

What it does:
1. Builds and pushes the Docker image (`IMAGE_REPO:latest`).
2. Uploads the required env vars to instance **metadata**.
3. Attaches `startup.sh` as the VM **startup‑script**.
4. Reboots the instance. On boot, the script installs Docker and runs the container.

View boot logs while it comes up:

```bash
gcloud compute instances get-serial-port-output "$INSTANCE_NAME" \
  --zone "$GCP_ZONE" --port 1 | tail -n 200
```

---

## Running on other providers (AWS, DO, Railway, etc.)

The app itself is **provider‑agnostic**. Any VPS that can run Docker works:

- Build & push the image: `docker build -t <yourrepo>/discord-gateway-bot:latest . && docker push <yourrepo>/discord-gateway-bot:latest`
- Provide the 4 runtime envs (`DISCORD_TOKEN`, `APPLICATION_ID`, `GUILD_ID`, `N8N_WEBHOOK_URL`).
- Run the container: `docker run -d --restart unless-stopped --env-file .env <yourrepo>/discord-gateway-bot:latest`

If the platform supports cloud‑init/user‑data, you can adapt `startup.sh` as a generic user‑data script.

---

## Security notes

- Never commit `.env` or real secrets. `.gitignore` already excludes `.env`.
- If you fork this repo, change the `IMAGE_REPO` in `.env` (or override when deploying).
- Rotate the Discord token if it ever leaks.

---

## License

MIT
