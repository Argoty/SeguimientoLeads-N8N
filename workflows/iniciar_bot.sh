#!/usr/bin/env bash
# Levanta el túnel de cloudflared, detecta la URL pública y registra
# el webhook de Telegram automáticamente.
#
# Requisitos:
#   - Token del bot en la variable TG_TOKEN o en un archivo .env junto a este script:
#         TG_TOKEN=123456:ABC...
#   - n8n corriendo y el workflow activo
#
# Uso:
#   ./iniciar_bot.sh              # túnel hacia n8n directo (puerto 5678)
#   PORT=5681 ./iniciar_bot.sh    # túnel hacia el puente .cjs
#
# Ctrl+C cierra el túnel.

set -euo pipefail

PORT="${PORT:-5678}"
WEBHOOK_PATH="/webhook/tg-leads"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar .env si TG_TOKEN no está definido
if [ -z "${TG_TOKEN:-}" ] && [ -f "$DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$DIR/.env"
  set +a
fi
: "${TG_TOKEN:?Falta TG_TOKEN. Define la variable o crea un archivo .env con TG_TOKEN=...}"

LOG="$(mktemp)"
cloudflared tunnel --url "http://localhost:${PORT}" >"$LOG" 2>&1 &
CF_PID=$!
trap 'kill "$CF_PID" 2>/dev/null || true; rm -f "$LOG"' EXIT INT TERM

echo "Levantando túnel hacia localhost:${PORT} ..."

# 1) Esperar la URL pública
URL=""
for _ in $(seq 1 60); do
  URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" | grep -v '^https://api\.' | head -n1 || true)"
  [ -n "$URL" ] && break
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "cloudflared se cerró inesperadamente:"; cat "$LOG"; exit 1
  fi
  sleep 1
done
[ -n "$URL" ] || { echo "No se obtuvo la URL del túnel."; cat "$LOG"; exit 1; }

# 2) Esperar a que el túnel esté realmente conectado
for _ in $(seq 1 90); do
  grep -q 'Registered tunnel connection' "$LOG" && break
  sleep 1
done
grep -q 'Registered tunnel connection' "$LOG" || { echo "El túnel no llegó a conectarse."; exit 1; }

# 3) Registrar el webhook en Telegram
echo "URL pública: ${URL}"
RESP="$(curl -sS -X POST "https://api.telegram.org/bot${TG_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"${URL}${WEBHOOK_PATH}\"}")"
echo "Telegram respondió: ${RESP}"

echo "${RESP}" | grep -q '"ok":true' || { echo "No se pudo registrar el webhook."; exit 1; }

echo
echo "Listo. Escríbele al bot. Ctrl+C para cerrar el túnel."
wait "$CF_PID"
