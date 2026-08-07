package services

import (
	"errors"
	"strings"

	"zapdesk/internal/models"
)

// Erros da sugestão de resposta (viram 4xx claros no handler).
var (
	ErrAIUnavailable  = errors.New("o Atendente IA não está configurado")
	ErrAINoBalance    = errors.New("sem saldo de tokens de IA")
	ErrAINothingToSay = errors.New("não há mensagem do cliente para responder")
)

// SuggestReply redige um RASCUNHO de resposta para o atendente humano revisar.
//
// Diferente do TriggerAIReply, aqui a IA NÃO envia nada: o texto volta para o
// compositor e quem decide é a pessoa. Por isso também não exige que a IA
// automática esteja ligada na empresa (é comum querer a IA só como apoio) nem
// que a conversa esteja liberada — só saldo de tokens. Consome os tokens usados,
// como qualquer chamada de IA.
func (s *SupportService) SuggestReply(accountID, ticketID string) (string, int, error) {
	if s.ai == nil || !s.ai.Configured() || s.aiRepo == nil {
		return "", 0, ErrAIUnavailable
	}
	cfg, err := s.aiRepo.GetConfig(accountID)
	if err != nil {
		return "", 0, err
	}
	if cfg == nil || cfg.TokenBalance <= 0 {
		return "", 0, ErrAINoBalance
	}
	msgs, err := s.repo.ListMessages(accountID, ticketID)
	if err != nil {
		return "", 0, err
	}
	system := s.buildAISystemPrompt(accountID, cfg.Instructions) + "\n\n" + suggestGuardrail
	chat := []AIChatMessage{{Role: "system", Content: system}}
	start := 0
	if len(msgs) > 12 {
		start = len(msgs) - 12
	}
	var sawInbound bool
	for _, m := range msgs[start:] {
		if m.Internal || m.Content == nil || *m.Content == "" {
			continue // nota interna a IA não lê
		}
		role := "user"
		if m.Direction == models.DirectionOut {
			role = "assistant"
		} else {
			sawInbound = true
		}
		chat = append(chat, AIChatMessage{Role: role, Content: *m.Content})
	}
	if !sawInbound {
		return "", 0, ErrAINothingToSay
	}
	// A última mensagem pode ser nossa (o atendente escreveu antes de pedir
	// ajuda). Um empurrão final orienta a IA a redigir mesmo assim.
	chat = append(chat, AIChatMessage{Role: "user", Content: suggestNudge})

	// Ticket vazio de propósito: no rascunho a IA não pode encaminhar nem mexer
	// na conversa — ela só escreve o texto.
	text, tokens, err := s.generateAIReply(accountID, "", chat)
	if err != nil {
		return "", tokens, err
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return "", tokens, ErrAINothingToSay
	}
	newBal, _ := s.aiRepo.ConsumeTokens(accountID, int64(tokens), ticketID)
	if s.billing != nil {
		go s.billing.MaybeCharge(accountID, newBal)
	}
	return text, tokens, nil
}

const suggestGuardrail = `# Modo rascunho
Você está escrevendo um RASCUNHO para um atendente humano revisar antes de enviar.
Escreva APENAS o texto da mensagem ao cliente — sem saudação a mais do que o normal,
sem explicar o que você fez, sem aspas, sem "Rascunho:" e sem opções numeradas.
Use o tom da empresa, seja direto e curto (no máximo 4 linhas). Se faltar informação
para responder com segurança, escreva a pergunta que o cliente precisa responder.`

const suggestNudge = `(instrução interna, não responda a esta linha: redija agora a próxima
mensagem ao cliente com base na conversa acima)`
