package services

import (
	"encoding/json"
	"testing"
)

// A tradução OpenAI→Anthropic é o ponto frágil do multi-IA: se o system virar
// mensagem, ou o resultado de ferramenta não virar bloco de user, a API recusa
// e a IA fica muda. Estes testes travam as três regras que importam.
func TestToAnthropicMessages(t *testing.T) {
	system, msgs := toAnthropicMessages([]map[string]any{
		{"role": "system", "content": "Você é útil."},
		{"role": "user", "content": "oi"},
		{"role": "assistant", "content": "vou consultar", "tool_calls": []map[string]any{{
			"id": "call_1", "type": "function",
			"function": map[string]any{"name": "acao_0", "arguments": `{"cpf":"123"}`},
		}}},
		{"role": "tool", "tool_call_id": "call_1", "content": "boleto em aberto"},
	})

	if system != "Você é útil." {
		t.Fatalf("system deveria sair das mensagens, veio %q", system)
	}
	if len(msgs) != 3 {
		t.Fatalf("esperava 3 mensagens (system fora), veio %d", len(msgs))
	}
	// O pedido de ferramenta vira bloco tool_use no assistant.
	blocos, ok := msgs[1]["content"].([]map[string]any)
	if !ok || len(blocos) != 2 || blocos[1]["type"] != "tool_use" {
		t.Fatalf("assistant deveria ter texto + tool_use, veio %#v", msgs[1]["content"])
	}
	if blocos[1]["id"] != "call_1" || blocos[1]["name"] != "acao_0" {
		t.Errorf("tool_use perdeu id/nome: %#v", blocos[1])
	}
	if input, _ := blocos[1]["input"].(map[string]any); input["cpf"] != "123" {
		t.Errorf("argumentos não viraram objeto: %#v", blocos[1]["input"])
	}
	// O resultado da ferramenta vira bloco tool_result num USER.
	if msgs[2]["role"] != "user" {
		t.Errorf("tool_result precisa ir no papel de user, veio %v", msgs[2]["role"])
	}
	res, _ := msgs[2]["content"].([]map[string]any)
	if len(res) != 1 || res[0]["type"] != "tool_result" || res[0]["tool_use_id"] != "call_1" {
		t.Errorf("tool_result malformado: %#v", msgs[2]["content"])
	}
}

// O laço reenvia a mensagem do assistant como ela voltou do JSON — isto é,
// tool_calls como []any, não []map[string]any. Se a conversão só aceitasse a
// forma tipada, a segunda rodada de qualquer ferramenta quebraria.
func TestToolCallsOfFromGenericJSON(t *testing.T) {
	var m map[string]any
	_ = json.Unmarshal([]byte(`{"role":"assistant","tool_calls":[
		{"id":"call_9","type":"function","function":{"name":"acao_1","arguments":"{\"placa\":\"ABC1D23\"}"}}]}`), &m)

	blocos := toolCallsOf(m["tool_calls"])
	if len(blocos) != 1 {
		t.Fatalf("esperava 1 bloco, veio %d", len(blocos))
	}
	if blocos[0]["id"] != "call_9" || blocos[0]["name"] != "acao_1" {
		t.Errorf("bloco perdeu id/nome: %#v", blocos[0])
	}
	if input, _ := blocos[0]["input"].(map[string]any); input["placa"] != "ABC1D23" {
		t.Errorf("argumentos não viraram objeto: %#v", blocos[0]["input"])
	}
}

func TestIsAnthropic(t *testing.T) {
	if !(&AIClient{baseURL: "https://api.anthropic.com/v1"}).isAnthropic() {
		t.Error("endpoint da Anthropic deveria usar o adaptador")
	}
	if (&AIClient{baseURL: "https://api.openai.com/v1"}).isAnthropic() {
		t.Error("endpoint OpenAI-compatível NÃO deveria usar o adaptador")
	}
}
