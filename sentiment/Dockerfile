FROM node:22-slim

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

COPY models.js server.js ./
# Bake the model weights (~150MB quantized) into the image so a fresh
# container boots scoring immediately instead of downloading on first poll.
ENV MODELS_DIR=/app/models
RUN npm run warmup

COPY public ./public

ENV PORT=10000
EXPOSE 10000

CMD ["node", "server.js"]
