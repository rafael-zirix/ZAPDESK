package services

import "testing"

// Marketing é campanha; o resto é conversa. É esse default que impede um modelo
// de promoção poluir a barra de mensagens prontas do atendimento.
func TestDefaultTemplateUsage(t *testing.T) {
	casos := map[string]string{
		"MARKETING":      TemplateUsageCampaign,
		"marketing":      TemplateUsageCampaign,
		"UTILITY":        TemplateUsageChat,
		"AUTHENTICATION": TemplateUsageChat,
		"":               TemplateUsageChat,
	}
	for categoria, esperado := range casos {
		if got := defaultTemplateUsage(categoria); got != esperado {
			t.Errorf("categoria %q: esperava %q, veio %q", categoria, esperado, got)
		}
	}
}
