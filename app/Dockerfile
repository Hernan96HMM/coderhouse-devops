# syntax=docker/dockerfile:1

# ---------- Etapa 1: dependencias de producción ----------
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund && npm cache clean --force

# ---------- Etapa 2: tests (falla el build si fallan los tests) ----------
FROM node:20-alpine AS test
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --no-audit --no-fund
COPY src ./src
COPY test ./test
RUN npm test

# ---------- Etapa 3: imagen final mínima ----------
FROM node:20-alpine AS runtime
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

# Fuerza a BuildKit a ejecutar la etapa "test": si los tests fallan, no hay imagen.
# (Sin esta dependencia, BuildKit omite las etapas que la imagen final no usa.)
RUN --mount=type=bind,from=test,source=/app/package.json,target=/tmp/tests-passed true

# La app solo necesita el binario "node" en runtime. Se eliminan npm, yarn y corepack
# de la imagen base: reducen el tamaño y la superficie de ataque (ej. CVE en npm/tar).
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /opt/yarn-* /usr/local/bin/yarn /usr/local/bin/yarnpkg

# Usuario no root
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app app

COPY --from=deps --chown=app:app /app/node_modules ./node_modules
COPY --chown=app:app package.json ./
COPY --chown=app:app src ./src

USER 10001
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "src/server.js"]
