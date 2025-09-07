#!/usr/bin/env bash
set -e
export COMPOSE_DOCKER_CLI_BUILD=1
export DOCKER_BUILDKIT=1

echo "Building and starting services..."
docker compose up -d --build

echo "Services started. Use 'docker compose ps' to view status."
