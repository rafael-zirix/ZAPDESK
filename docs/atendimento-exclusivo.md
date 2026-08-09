# Exclusividade do atendimento

> Decisão do dono do produto (08/08/2026). Vale para o painel web e o app.

**Assumida a conversa, só o responsável fala com o cliente.** Quem quiser atender
precisa receber a transferência — **nem o administrador responde por cima**.

A regra vive no **servidor** (`internal/services/support_assignment.go`). Esconder
o botão na tela não bastaria: um POST direto na API furaria a regra.

## O que cada um pode

| Ação | Sem dono | Responsável | Outro atendente | Admin |
|---|---|---|---|---|
| Responder ao cliente (texto, anexo, áudio, modelo, localização, contato, botões, reenvio) | ✅ | ✅ | ❌ 403 | ❌ 403 |
| **Nota interna** | ✅ | ✅ | ✅ | ✅ |
| Assumir | ✅ | — | ❌ 403 | ✅ |
| Transferir | ✅ | ✅ | ❌ 403 | ✅ |
| Etiquetar, resolver, ver histórico | ✅ | ✅ | ✅ | ✅ |

A nota interna fica de fora de propósito: ela não chega ao cliente e é como um
colega passa informação para quem está atendendo.

Ações do sistema (Atendente IA, campanhas, bot) passam com `userID` vazio e
**não** são bloqueadas — não pertencem a ninguém.

## Válvula de escape: liberação automática

Conversa presa com um atendente que sumiu volta sozinha para a fila.

O critério é **"o cliente está esperando"**: a última mensagem da conversa é do
cliente e chegou há mais tempo que o prazo da conta. Quem assumiu, respondeu e
está aguardando o cliente **não** perde a conversa por ter saído para almoçar.

Cada liberação registra no histórico: *"Devolvida à fila automaticamente: o
cliente ficou aguardando resposta."*

O worker roda de minuto em minuto (`StartTicketReleaseWorker`).

## Configuração (por empresa)

Duas colunas em `accounts` (migração `000045`):

| Coluna | Padrão | O que faz |
|---|---|---|
| `exclusive_assignment` | `true` | Liga a regra. `false` volta ao comportamento antigo (qualquer atendente responde qualquer conversa). |
| `release_after_minutes` | `30` | Minutos de cliente esperando até a conversa voltar à fila. `0` desliga a liberação automática. |

Hoje só por SQL — ainda não há tela para isso:

```sql
UPDATE accounts SET release_after_minutes = 45 WHERE id = '<conta>';
```

## Como a tela se comporta

- **Faixa no topo da conversa**: "Em atendimento com Fulano" (com botão *Assumir* só para admin).
- **Compositor bloqueado**: campo desabilitado, cadeado no lugar do microfone e a explicação "peça a transferência para responder".
- **Nota interna continua funcionando** com a conversa bloqueada — a faixa muda de texto para deixar claro que aquilo não vai ao cliente.
- Se a conversa for assumida por outro **enquanto o atendente digitava**, o envio volta 403, o texto é devolvido ao campo (não se perde) e o motivo aparece na tela.

## Portas dos fundos já fechadas

Uma revisão adversarial procurou furos na regra. Estes existiam e foram fechados
— servem de lembrete de que a exclusividade tem de valer em **todo caminho que
produz mensagem ao cliente**, não só no botão de enviar:

| Furo | Por que funcionava |
|---|---|
| **Assumir** a conversa do colega | `claim` não olhava se já havia dono — bastava um clique para tomar e responder |
| **Fechar** a conversa do colega | a próxima mensagem do cliente criava um ticket novo **sem dono**, liberado para qualquer um |
| **Retomar a IA** na conversa do colega | o bot respondia ao cliente no lugar dele |
| **Reenviar** uma nota interna | nota é `direction='out'`; o retry a mandava ao cliente |
| Modo **nota** reabria o anexo (app) | o "+" voltava a ficar ativo e mandava foto/localização ao cliente |
| IA respondia por cima | só o envio de TEXTO pausava o bot; anexo, modelo e localização não |

Duas decisões de projeto que vieram junto:

- **Falha fechado**: se a consulta da política falhar, o envio é recusado. Deixar
  passar transformaria um blip do banco em "todo mundo responde tudo", sem
  ninguém perceber.
- **Quem arbitra corrida é o banco**: `Assumir` e a liberação automática usam
  `UPDATE` condicional. Dois cliques simultâneos não deixam mais os dois
  atendentes achando que a conversa é sua.

## Onde mexer

| Arquivo | Papel |
|---|---|
| `internal/services/support_assignment.go` | `ensureAssignee`, `ensureCanSend`, worker de liberação |
| `internal/services/support_lifecycle_service.go` | travas de `ClaimTicket` e `TransferTicket` |
| `internal/repository/support_repository.go` | `AccountAssignmentPolicy`, `StaleAssignedTickets` |
| `app/lib/inbox/conversation_controller.dart` | `lockedByOther` / `lockedByName` (serve painel e app) |
