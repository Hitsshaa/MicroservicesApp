@echo off
SETLOCAL ENABLEDELAYEDEXPANSION
set COMPOSE_DOCKER_CLI_BUILD=1
set DOCKER_BUILDKIT=1

echo Building and starting services...
docker compose up -d --build

echo Services started. Use "docker compose ps" to view status.
ENDLOCAL
