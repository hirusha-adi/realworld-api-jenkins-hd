FROM node:20-alpine AS build

WORKDIR /app

RUN apk add --no-cache openssl

COPY package*.json ./
COPY nx.json ./
COPY tsconfig*.json ./
COPY jest.config.ts ./
COPY jest.preset.js ./
COPY project.json ./
COPY newrelic.js ./
COPY src ./src

RUN npm ci
RUN npx prisma generate --schema=src/prisma/schema.prisma
RUN npx nx build api


FROM node:20-alpine AS runtime

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
ENV NPM_CONFIG_CACHE=/tmp/.npm

RUN apk add --no-cache openssl \
    && addgroup -S api \
    && adduser -S -G api api

WORKDIR /app

COPY --from=build /app/dist/api ./api
COPY --from=build /app/src/prisma ./api/prisma
COPY --from=build /app/newrelic.js ./api/newrelic.js
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN npm --prefix api --omit=dev -f install \
    && npm --prefix api install prisma@4.16.2 --omit=dev \
    && cd /app/api \
    && npx prisma generate --schema=prisma/schema.prisma \
    && chmod +x /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /tmp/.npm \
    && chown -R api:api /app /tmp/.npm

USER api

WORKDIR /app/api

EXPOSE 3000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "main.js"]
