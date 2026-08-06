package services

import (
	"strings"
	"testing"

	"zapdesk/internal/models"
)

// O texto registrado na conversa deve ser o corpo do modelo com as variáveis
// já substituídas — inclusive o curinga {nome}.
func TestCampaignMessageText(t *testing.T) {
	nome := "Rafael Campos"
	rec := models.CampaignRecipient{ContactName: &nome}
	params := personalizeParams([]string{"{nome}", "20% OFF"}, rec)

	body := "Olá {{1}}, temos {{2}} para você!"
	out := body
	for i, p := range params {
		out = strings.ReplaceAll(out, placeholder(i+1), p)
	}
	want := "Olá Rafael Campos, temos 20% OFF para você!"
	if out != want {
		t.Fatalf("texto errado:\n  obtido: %s\n  esperado: %s", out, want)
	}
}

// Sem nome cadastrado, o {nome} vira "cliente" (nunca fica em branco).
func TestCampaignMessageTextSemNome(t *testing.T) {
	params := personalizeParams([]string{"{nome}"}, models.CampaignRecipient{})
	if params[0] != "cliente" {
		t.Fatalf("esperava 'cliente', veio %q", params[0])
	}
}
