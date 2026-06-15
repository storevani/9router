#!/usr/bin/env sh
set -eu

cd /root/9router
docker compose pull 9router
docker compose up -d --remove-orphans 9router
docker image prune -f
