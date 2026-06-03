FROM node:22-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl jq git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /app
COPY daemon.sh summarize.sh ./
RUN chmod +x daemon.sh summarize.sh

ENTRYPOINT ["/app/daemon.sh"]
