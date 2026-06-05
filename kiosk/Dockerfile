FROM node:22-slim

WORKDIR /app
COPY package.json server.js ./
COPY public ./public

ENV PORT=10000
EXPOSE 10000

CMD ["node", "server.js"]
