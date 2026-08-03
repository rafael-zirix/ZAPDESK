#!/usr/bin/env bash
# Deploy do zapdesk na VM Oracle (co-hospedado com o CRM).
# Cross-compila o backend arm64 + build web no Mac, empacota e sobe.
# Requer: deploy/.env preenchido (segredos de produção, fora do git).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VM="opc@167.126.11.122"
KEY="$HOME/.ssh/oracle_ubuntu"
URL="https://hotzap.com.br"

echo "==> build backend (linux/arm64)"
( cd "$ROOT/backend" && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -o "$ROOT/deploy/zapdesk-api" ./cmd/api )

echo "==> build web (Flutter)"
# App servido em /app/ (a raiz "/" é a landing do cliente).
( cd "$ROOT/app" && flutter build web --release --no-tree-shake-icons --pwa-strategy=none --base-href /app/ --dart-define=API_BASE_URL="$URL" >/dev/null )

echo "==> empacota"
rm -rf "$ROOT/deploy/migrations" "$ROOT/deploy/web"
cp -r "$ROOT/backend/migrations" "$ROOT/deploy/migrations"
# App Flutter (base-href /app/) em web/app; a landing (start.html) vira a home "/".
mkdir -p "$ROOT/deploy/web/app"
cp -r "$ROOT/app/build/web/." "$ROOT/deploy/web/app/"
mv "$ROOT/deploy/web/app/start.html" "$ROOT/deploy/web/index.html"
# favicon acessível na raiz (a landing referencia /favicon.png).
cp "$ROOT/app/build/web/favicon.png" "$ROOT/deploy/web/favicon.png" 2>/dev/null || true
# SW de "auto-destruição" na RAIZ: navegadores que já abriram o app na raiz têm um
# service worker registrado no escopo "/", que continuaria servindo o app velho em
# cache no lugar da nova landing. Este arquivo substitui o /flutter_service_worker.js
# antigo: limpa os caches, se desregistra e recarrega a aba. (O app novo em /app/
# roda com --pwa-strategy=none, sem SW.)
cat > "$ROOT/deploy/web/flutter_service_worker.js" <<'SW'
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    try { for (const k of await caches.keys()) await caches.delete(k); } catch (_) {}
    try { await self.registration.unregister(); } catch (_) {}
    try { for (const c of await self.clients.matchAll()) c.navigate(c.url); } catch (_) {}
  })());
});
SW
tar czf /tmp/zapdesk-deploy.tgz -C "$ROOT/deploy" Dockerfile docker-compose.prod.yml .env zapdesk-api migrations web 2>/dev/null

echo "==> envia e sobe (build da imagem + force-recreate)"
scp -i "$KEY" /tmp/zapdesk-deploy.tgz "$VM":~/ >/dev/null
ssh -i "$KEY" "$VM" '
  set -e
  mkdir -p ~/zapdesk-deploy
  tar xzf ~/zapdesk-deploy.tgz -C ~/zapdesk-deploy 2>/dev/null
  rm -f ~/zapdesk-deploy.tgz
  cd ~/zapdesk-deploy
  docker build -q -t zapdesk-api:arm64 . >/dev/null
  docker compose -f docker-compose.prod.yml up -d --force-recreate zapdesk-api
' 2>&1 | grep -vE "xattr|provenance|quarantine" || true

echo "==> health"
sleep 3
curl -s -o /dev/null -w "  %{http_code}  $URL/health\n" "$URL/health"
echo "==> pronto"
