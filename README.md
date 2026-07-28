# Zapdesk

Plataforma SaaS de atendimento via WhatsApp (multi-cliente). Painel estilo
WhatsApp Web + app mobile, com equipe, setores, histórico e mídia.

> Nome de trabalho — a definir. Destacado da Central de Atendimento do ZXtrack,
> reaproveitando o núcleo já validado em produção (Meta Cloud API, tickets, bot).
> Arquitetura e roadmap: `~/Documents/SaaS-WhatsApp/arquitetura-e-roadmap.md`.

## Estrutura

```
backend/    API Go (Gin + PostgreSQL), multi-tenant por account_id
  cmd/api           entrypoint
  internal/         config, database, handlers, middleware, models,
                    repository, services, router
  migrations/       golang-migrate (aplicadas no startup)
web/        (fase futura) painel Flutter Web
mobile/     (fase futura) app Flutter iOS/Android
```

## Rodar o backend (dev)

```bash
cd backend
cp .env.example .env      # ajuste se necessário
make up                   # sobe Postgres + API (Docker)
curl localhost:8080/health
```

Ou local (Postgres no ar):

```bash
cd backend
make up                   # só o Postgres
make dev                  # roda a API com go run
```

## Roadmap (resumo)

- [x] **Fase 0** — Fundação: estrutura, config, banco, migrações, health.
- [ ] **Fase 1** — MVP web: auth (OTP+JWT), usuários, inbox (contatos + conversa + texto), 1 número Meta.
- [ ] **Fase 2** — Mídia (foto/documento/áudio).
- [ ] **Fase 3** — Multi-número (Embedded Signup da Meta).
- [ ] **Fase 4** — Billing (assinatura + repasse Meta).
- [ ] **Fase 5** — App mobile.
