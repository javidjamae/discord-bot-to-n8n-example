# Node 20 Alpine - pinned for reproducible builds
FROM node:20.14-alpine

ENV NODE_ENV=production

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

COPY index.js ./

# Non-root user and correct ownership
RUN addgroup -S app && adduser -S app -G app \
  && chown -R app:app /app
USER app

# Image metadata
LABEL org.opencontainers.image.source="https://github.com/javidjamae/discord-gateway-bot" \
      org.opencontainers.image.description="Discord Gateway Bot that routes slash commands to n8n" \
      org.opencontainers.image.licenses="MIT"

CMD ["node", "index.js"]