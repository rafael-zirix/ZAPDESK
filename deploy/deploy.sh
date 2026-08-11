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
( cd "$ROOT/app" && flutter build web --release --no-tree-shake-icons --pwa-strategy=none --base-href /app/ --no-web-resources-cdn --dart-define=API_BASE_URL="$URL" >/dev/null )

echo "==> build do app de celular pelo navegador (/m)"
# Mesmo código do app nativo (lib/main_mobile.dart), servido como página em /m/.
# Serve na MESMA ORIGEM da API de propósito: hospedado em outro host, o navegador
# barra as chamadas por CORS e o atendente só vê "erro ao enviar o código".
( cd "$ROOT/app" && flutter build web --release --no-tree-shake-icons --pwa-strategy=none --base-href /m/ --no-web-resources-cdn -t lib/main_mobile.dart --dart-define=API_BASE_URL="$URL" --output build/web-mobile >/dev/null )

echo "==> empacota"
rm -rf "$ROOT/deploy/migrations" "$ROOT/deploy/web"
cp -r "$ROOT/backend/migrations" "$ROOT/deploy/migrations"
# App Flutter (base-href /app/) em web/app; a landing (start.html) vira a home "/".
mkdir -p "$ROOT/deploy/web/app"
cp -r "$ROOT/app/build/web/." "$ROOT/deploy/web/app/"
mv "$ROOT/deploy/web/app/start.html" "$ROOT/deploy/web/index.html"
# Páginas legais na RAIZ do site (a Meta exige política de privacidade e
# instruções de exclusão de dados; o router serve com URL limpa: /privacidade…).
for f in privacidade.html termos.html exclusao-de-dados.html legal.css start.js; do
  mv "$ROOT/deploy/web/app/$f" "$ROOT/deploy/web/$f" 2>/dev/null || true
done
# favicon acessível na raiz (a landing referencia /favicon.png).
cp "$ROOT/app/build/web/favicon.png" "$ROOT/deploy/web/favicon.png" 2>/dev/null || true

# App de celular em web/m (URL: /m). As metas abaixo são o que faz o
# "Adicionar à Tela de Início" abrir em tela cheia, com ícone e nome próprios —
# sem elas o atendente ganha só um atalho do Safari, com barra de endereço.
mkdir -p "$ROOT/deploy/web/m"
cp -r "$ROOT/app/build/web-mobile/." "$ROOT/deploy/web/m/"
python3 - "$ROOT/deploy/web/m/index.html" <<'PY'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text()
metas = '''
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="HotZap">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#0E9384">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
'''
t = re.sub(r'<meta name="viewport"[^>]*>\s*', '', t, count=1)
if 'apple-mobile-web-app-capable' not in t:
    t = t.replace('</head>', metas + '</head>')
t = t.replace('<title>zapdesk_app</title>', '<title>HotZap</title>')
p.write_text(t)
PY
# As páginas legais e a landing são da RAIZ: não precisam ir dentro de /m.
for f in privacidade.html termos.html exclusao-de-dados.html legal.css start.html; do
  rm -f "$ROOT/deploy/web/m/$f"
done
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
  # Limpa migrations/web antes de extrair: tar não remove arquivos que sumiram do
  # pacote, e um .sql órfão de um deploy antigo derruba o boot com "duplicate
  # migration file". web idem, para não servir asset velho.
  rm -rf ~/zapdesk-deploy/migrations ~/zapdesk-deploy/web
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
