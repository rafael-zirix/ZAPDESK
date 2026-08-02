package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// AIClient fala com um provedor de IA compatível com a API OpenAI (Groq, Gemini
// no modo OpenAI, Ollama, etc.). Neutro: troca só base URL / chave / modelo.
type AIClient struct {
	baseURL string
	apiKey  string
	model   string
	http    *http.Client
}

func NewAIClient(baseURL, apiKey, model string) *AIClient {
	return &AIClient{
		baseURL: strings.TrimRight(baseURL, "/"),
		apiKey:  apiKey,
		model:   model,
		http:    &http.Client{Timeout: 60 * time.Second},
	}
}

// Configured indica se há provedor de IA pronto para usar.
func (c *AIClient) Configured() bool { return c != nil && c.baseURL != "" && c.model != "" }

// AIChatMessage é uma mensagem no formato OpenAI (role: system|user|assistant).
type AIChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// Complete gera uma resposta e devolve o texto + o total de tokens usados
// (prompt + completion) — para descontar do saldo da empresa.
func (c *AIClient) Complete(messages []AIChatMessage, maxTokens int) (string, int, error) {
	if !c.Configured() {
		return "", 0, errors.New("motor de IA não configurado")
	}
	if maxTokens <= 0 {
		maxTokens = 500
	}
	body := map[string]any{
		"model":       c.model,
		"messages":    messages,
		"max_tokens":  maxTokens,
		"temperature": 0.3,
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.baseURL+"/chat/completions", bytes.NewReader(raw))
	if err != nil {
		return "", 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return "", 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", 0, fmt.Errorf("ia respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Usage struct {
			TotalTokens      int `json:"total_tokens"`
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", 0, err
	}
	if len(out.Choices) == 0 {
		return "", 0, errors.New("a IA não devolveu resposta")
	}
	total := out.Usage.TotalTokens
	if total == 0 {
		total = out.Usage.PromptTokens + out.Usage.CompletionTokens
	}
	return strings.TrimSpace(out.Choices[0].Message.Content), total, nil
}

// AITool descreve uma ferramenta (function) que a IA pode chamar (1 parâmetro string).
type AITool struct {
	Name        string
	Description string
	ParamName   string
	ParamDesc   string
}

// AIToolCall é um pedido da IA para executar uma ferramenta.
type AIToolCall struct {
	ID       string
	Name     string
	ArgsJSON string
}

// ChatRaw envia mensagens no formato OpenAI (mapas livres, para suportar tool_calls
// e mensagens de resultado) + ferramentas opcionais. Devolve o texto final OU os
// tool_calls pedidos pela IA, mais os tokens usados. Gemini suporta no modo OpenAI.
func (c *AIClient) ChatRaw(messages []map[string]any, tools []AITool, maxTokens int) (string, []AIToolCall, map[string]any, int, error) {
	if !c.Configured() {
		return "", nil, nil, 0, errors.New("motor de IA não configurado")
	}
	if maxTokens <= 0 {
		maxTokens = 500
	}
	body := map[string]any{
		"model":       c.model,
		"messages":    messages,
		"max_tokens":  maxTokens,
		"temperature": 0.3,
	}
	if len(tools) > 0 {
		ts := make([]map[string]any, 0, len(tools))
		for _, t := range tools {
			ts = append(ts, map[string]any{
				"type": "function",
				"function": map[string]any{
					"name":        t.Name,
					"description": t.Description,
					"parameters": map[string]any{
						"type": "object",
						"properties": map[string]any{
							t.ParamName: map[string]any{"type": "string", "description": t.ParamDesc},
						},
						"required": []string{t.ParamName},
					},
				},
			})
		}
		body["tools"] = ts
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, c.baseURL+"/chat/completions", bytes.NewReader(raw))
	if err != nil {
		return "", nil, nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+c.apiKey)
	}
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
		Choices []struct {
			Message json.RawMessage `json:"message"`
		} `json:"choices"`
		Usage struct {
			TotalTokens      int `json:"total_tokens"`
			PromptTokens     int `json:"prompt_tokens"`
			CompletionTokens int `json:"completion_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", nil, nil, 0, err
	}
	total := out.Usage.TotalTokens
	if total == 0 {
		total = out.Usage.PromptTokens + out.Usage.CompletionTokens
	}
	if len(out.Choices) == 0 {
		return "", nil, nil, total, errors.New("a IA não devolveu resposta")
	}
	// Guarda a mensagem do assistant CRUA para reenviar igual na próxima ida (o Gemini
	// exige campos como thought_signature nos tool_calls; remontar quebra a continuação).
	rawMsg := map[string]any{}
	_ = json.Unmarshal(out.Choices[0].Message, &rawMsg)
	var msg struct {
		Content   string `json:"content"`
		ToolCalls []struct {
			ID       string `json:"id"`
			Function struct {
				Name      string `json:"name"`
				Arguments string `json:"arguments"`
			} `json:"function"`
		} `json:"tool_calls"`
	}
	_ = json.Unmarshal(out.Choices[0].Message, &msg)
	var calls []AIToolCall
	for _, tc := range msg.ToolCalls {
		calls = append(calls, AIToolCall{ID: tc.ID, Name: tc.Function.Name, ArgsJSON: tc.Function.Arguments})
	}
	return strings.TrimSpace(msg.Content), calls, rawMsg, total, nil
}
