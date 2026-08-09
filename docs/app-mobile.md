# App de celular (HotZap Mobile)

App de atendimento para Android/iOS com a cara do WhatsApp. Vive no MESMO projeto
Flutter do painel (`app/`), num entrypoint separado — os dois compartilham
`api_client`, os modelos e os controllers do inbox, então corrigir uma regra de
negócio vale para os dois.

| | Painel web | App de celular |
|---|---|---|
| Entrypoint | `lib/main.dart` | `lib/main_mobile.dart` |
| Telas | `lib/inbox/`, `lib/shell/`… | `lib/mobile/` |
| Compartilhado | `lib/core/`, `lib/models/`, `lib/inbox/*_controller.dart` | idem |

## Rodar em desenvolvimento

```bash
cd ~/zapdesk/app && flutter run -t lib/main_mobile.dart --dart-define=API_BASE_URL=http://10.0.2.2:8082
```

`10.0.2.2` é como o emulador Android enxerga o `localhost` da máquina. Em
aparelho físico, use o IP da máquina na rede (ex.: `http://192.168.0.10:8082`).

Para conferir só o layout, o app roda no navegador (com os plugins na versão web):

```bash
cd ~/zapdesk/app && flutter run -d chrome -t lib/main_mobile.dart --dart-define=API_BASE_URL=http://localhost:8082
```

## Gerar o APK

```bash
cd ~/zapdesk/app && flutter build apk --release -t lib/main_mobile.dart --dart-define=API_BASE_URL=https://hotzap.com.br
```

Sai em `build/app/outputs/flutter-apk/app-release.apk` (~52 MB). Hoje é assinado
com a chave de DEBUG — serve para instalar e testar, **não** para publicar na
Play Store (para a loja é preciso criar uma keystore e um `signingConfig`).

`applicationId`: `br.com.hotzap.app`.

## O que o app faz

Assumir conversa · transferir (atendente ou setor) · etiquetas · nota interna ·
ligar/pausar a IA na conversa · rascunho da IA · mensagens prontas (respostas
rápidas + modelos aprovados) · anexo (documento, câmera, galeria) · localização ·
cartão de contato · áudio "segurar para gravar" · resolver/reabrir/aguardando ·
histórico · fila ("pegar próximo") · presença disponível/ausente · busca ·
tema claro/escuro · contador da janela de 24h no cabeçalho ·
**responder citando** (segure a mensagem → Responder) · **encaminhar** para outra
conversa.

A regra de quem pode responder está em
[atendimento-exclusivo.md](atendimento-exclusivo.md) — com a conversa de outro
atendente, o compositor aparece bloqueado (mas a nota interna continua).

Canais: WhatsApp e Instagram Direct (o selo no avatar mostra de onde o cliente veio).

## Notificação push (Firebase)

O código está pronto nas duas pontas, mas **exige um projeto Firebase** para
funcionar. Sem ele o app roda normalmente — só não avisa com a tela apagada
(a lista se atualiza a cada 10s enquanto o app está aberto).

### 1. No console do Firebase (uma vez)

1. Criar um projeto (ex.: "HotZap").
2. Adicionar um app **Android** com o pacote `br.com.hotzap.app`.
3. Baixar o `google-services.json` e salvar em `app/android/app/google-services.json`.
   O Gradle detecta o arquivo e liga o Firebase sozinho (ver `app/build.gradle.kts`).
4. Em *Configurações do projeto → Contas de serviço*, gerar uma **chave privada**
   (JSON da service account) — é o que o backend usa para enviar.

### 2. No servidor

Colocar o JSON da service account na VM e apontar no `.env`:

```
FCM_CREDENTIALS_FILE=/app/fcm-service-account.json
```

O arquivo precisa estar acessível dentro do contêiner (montar um volume no
`docker-compose.prod.yml`). Sem a variável, o serviço sobe inerte e registra
"push: credencial do Firebase não pôde ser lida" no log — nada quebra.

### Como funciona

- O app registra o token do aparelho em `POST /devices` depois do login e o
  remove em `DELETE /devices/:token` no logout.
- Quando chega mensagem do cliente (`ProcessInbound`, `ProcessInboundMedia` e o
  Direct do Instagram), o backend notifica **o dono da conversa**; se ninguém
  assumiu, os atendentes do **setor** da fila; e, na falta dos dois, a empresa
  toda.
- Token que o FCM devolve como inexistente (app desinstalado) é apagado sozinho.
- Tocar na notificação abre a conversa correspondente.

Tabela: `device_tokens` (migração `000040`).

## Limitações conhecidas

- **iOS**: o código é o mesmo, mas falta gerar o build assinado (conta Apple
  Developer) e adicionar o `GoogleService-Info.plist` + chave APNs para push.
- **Instagram Direct**: a UI trata o canal, mas a entrada real depende de o app
  da Meta (Zap_Zirix) receber as permissões `pages_*`/`instagram_*`.
- **Assinatura do APK**: chave de debug (ver acima).
