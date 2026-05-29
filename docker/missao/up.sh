#!/usr/bin/env bash
# Build local + up do Evolution GO na porta 4005 pra ambiente Missão.
# Usa podman se disponível; fallback pra docker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---------- Detecta runtime ----------
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  RUNTIME="podman"
  COMPOSE=(podman compose)
elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  RUNTIME="docker"
  COMPOSE=(docker compose)
else
  echo "ERRO: podman nem docker disponíveis/rodando. Inicie um dos dois." >&2
  exit 1
fi

echo "-> Runtime: $RUNTIME"

# ---------- Garante .env ----------
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    echo "-> .env não existe. Copiando de .env.example..."
    cp .env.example .env
    echo "   Edite .env com suas credenciais antes de continuar se necessário."
  else
    echo "ERRO: nem .env nem .env.example encontrados." >&2
    exit 1
  fi
fi

# ---------- Build + up ----------
echo "-> Build + up (pode demorar alguns minutos na primeira vez)..."
"${COMPOSE[@]}" up -d --build --force-recreate

# ---------- Status ----------
echo
echo "-> Containers:"
"${COMPOSE[@]}" ps
echo
echo "Evolution GO: http://localhost:4005"
echo "Manager web:  http://localhost:4005/manager"
echo
echo "Para acompanhar logs:"
echo "  ${COMPOSE[*]} logs -f evolution-go"
