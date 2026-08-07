package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// A Anthropic NÃO fala o protocolo OpenAI: o endpoint é /messages, a chave vai
// em x-api-key, o system sai de dentro das mensagens e as ferramentas usam
// blocos de conteúdo em vez de tool_calls. Este arquivo traduz nos dois
// sentidos, para o resto do sistema continuar falando um formato só.
//
// A tradução é de ida e volta: recebemos histórico no formato OpenAI, mandamos
// no formato Anthropic e devolvemos a resposta de novo no formato OpenAI — assim
// o laço de function-calling do Atendente IA não muda em nada.

// isAnthropic diz se este cliente aponta para a API da Anthropic.
func (c *AIClient) isAnthropic() bool {
	return strings.Contains(strings.ToLower(c.baseURL), "anthropic.com")
}

// chatAnthropic é o equivalente do ChatRaw falando o protocolo da Anthropic.
func (c *AIClient) chatAnthropic(messages []map[string]any, tools []AITool, maxTokens int) (string, []AIToolCall, map[string]any, int, error) {
	if maxTokens <= 0 {
		maxTokens = 500
	}
	system, msgs := toAnthropicMessages(messages)
	body := map[string]any{
		"model":      c.model,
		"max_tokens": maxTokens,
		"messages":   msgs,
	}
	if system != "" {
		body["system"] = system
	}
	if len(tools) > 0 {
		ts := make([]map[string]any, 0, len(tools))
		for _, t := range tools {
			ts = append(ts, map[string]any{
				"name":        t.Name,
				"description": t.Description,
				"input_schema": map[string]any{
					"type": "object",
					"properties": map[string]any{
						t.ParamName: map[string]any{"type": "string", "description": t.ParamDesc},
					},
					"required": []string{t.ParamName},
				},
			})
		}
		body["tools"] = ts
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, strings.TrimSuffix(c.baseURL, "/")+"/messages", bytes.NewReader(raw))
	if err != nil {
		return "", nil, nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", c.apiKey) // Anthropic não usa Bearer
	req.Header.Set("anthropic-version", "2023-06-01")
	resp, err := c.http.Do(req)
	if err != nil {
		return "", nil, nil, 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", nil, nil, 0, fmt.Errorf("ia respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Content []struct {
			Type  string          `json:"type"`
			Text  string          `json:"text"`
			ID    string          `json:"id"`
			Name  string          `json:"name"`
			Input json.RawMessage `json:"input"`
		} `json:"content"`
		Usage struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", nil, nil, 0, err
	}
	total := out.Usage.InputTokens + out.Usage.OutputTokens

	var texto strings.Builder
	var calls []AIToolCall
	toolCalls := []map[string]any{}
	for _, b := range out.Content {
		switch b.Type {
		case "text":
			texto.WriteString(b.Text)
		case "tool_use":
			args := string(b.Input)
			if args == "" {
				args = "{}"
			}
			calls = append(calls, AIToolCall{ID: b.ID, Name: b.Name, ArgsJSON: args})
			toolCalls = append(toolCalls, map[string]any{
				"id": b.ID, "type": "function",
				"function": map[string]any{"name": b.Name, "arguments": args},
			})
		}
	}
	// Devolve a mensagem do assistant no formato OpenAI: é assim que o laço a
	// reenvia, e a conversão de ida a traduz de volta na próxima rodada.
	rawMsg := map[string]any{"role": "assistant", "content": texto.String()}
	if len(toolCalls) > 0 {
		rawMsg["tool_calls"] = toolCalls
	}
	if texto.Len() == 0 && len(calls) == 0 {
		return "", nil, rawMsg, total, errors.New("a IA não devolveu resposta")
	}
	return strings.TrimSpace(texto.String()), calls, rawMsg, total, nil
}

// toAnthropicMessages separa o system e converte o histórico OpenAI em blocos da
// Anthropic. Regras que valem: o system é parâmetro de topo (não mensagem);
// pedido de ferramenta vira bloco `tool_use` no assistant; resultado de
// ferramenta vira bloco `tool_result` numa mensagem de USER.
func toAnthropicMessages(messages []map[string]any) (string, []map[string]any) {
	var system strings.Builder
	out := make([]map[string]any, 0, len(messages))
	for _, m := range messages {
		role, _ := m["role"].(string)
		switch role {
		case "system":
			if s, ok := m["content"].(string); ok && s != "" {
				if system.Len() > 0 {
					system.WriteString("\n\n")
				}
				system.WriteString(s)
			}
		case "tool":
			// Resultado de ferramenta: a Anthropic espera no papel de user.
			out = append(out, map[string]any{
				"role": "user",
				"content": []map[string]any{{
					"type":        "tool_result",
					"tool_use_id": textOf(m["tool_call_id"]),
					"content":     textOf(m["content"]),
				}},
			})
		case "assistant":
			blocos := []map[string]any{}
			if s := textOf(m["content"]); s != "" {
				blocos = append(blocos, map[string]any{"type": "text", "text": s})
			}
			for _, tc := range toolCallsOf(m["tool_calls"]) {
				blocos = append(blocos, tc)
			}
			if len(blocos) == 0 {
				continue // assistant vazio: a Anthropic recusa
			}
			out = append(out, map[string]any{"role": "assistant", "content": blocos})
		default:
			if s := textOf(m["content"]); s != "" {
				out = append(out, map[string]any{"role": "user", "content": s})
			}
		}
	}
	return system.String(), out
}

// toolCallsOf converte tool_calls do formato OpenAI em blocos tool_use.
func toolCallsOf(v any) []map[string]any {
	lista, ok := v.([]map[string]any)
	if !ok {
		// Veio de um json.Unmarshal genérico (o rawMsg reenviado pelo laço).
		bruto, _ := v.([]any)
		for _, item := range bruto {
			if m, ok := item.(map[string]any); ok {
				lista = append(lista, m)
			}
		}
	}
	out := make([]map[string]any, 0, len(lista))
	for _, tc := range lista {
		fn, _ := tc["function"].(map[string]any)
		if fn == nil {
			continue
		}
		var input map[string]any
		if err := json.Unmarshal([]byte(textOf(fn["arguments"])), &input); err != nil || input == nil {
			input = map[string]any{}
		}
		out = append(out, map[string]any{
			"type":  "tool_use",
			"id":    textOf(tc["id"]),
			"name":  textOf(fn["name"]),
			"input": input,
		})
	}
	return out
}

func textOf(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	if v == nil {
		return ""
	}
	return fmt.Sprintf("%v", v)
}
