#!/bin/sh
set -e

echo "Applying Prisma migrations..."
npx prisma migrate deploy --schema prisma/schema.prisma

echo "Starting application..."

exec "$@"
