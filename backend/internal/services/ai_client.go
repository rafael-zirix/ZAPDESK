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
