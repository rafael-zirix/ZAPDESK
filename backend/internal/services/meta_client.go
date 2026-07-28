package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// MetaClient fala com a WhatsApp Cloud API (Graph). Nesta fase as credenciais
// são globais (um número de teste); na fase multi-número virão por conta.
type MetaClient struct {
	apiBase       string
	token         string
	phoneNumberID string
	http          *http.Client
}

func NewMetaClient(apiBase, token, phoneNumberID string) *MetaClient {
	return &MetaClient{
		apiBase:       apiBase,
		token:         token,
		phoneNumberID: phoneNumberID,
		http:          &http.Client{Timeout: 20 * time.Second},
	}
}

// Configured indica se há credenciais para enviar.
func (c *MetaClient) Configured() bool { return c.token != "" && c.phoneNumberID != "" }

// SendText envia uma mensagem de texto e devolve o wamid.
func (c *MetaClient) SendText(to, text string) (string, error) {
	body := map[string]any{
		"messaging_product": "whatsapp",
		"to":                to,
		"type":              "text",
		"text":              map[string]string{"body": text},
	}
	raw, _ := json.Marshal(body)
	url := fmt.Sprintf("%s/%s/messages", c.apiBase, c.phoneNumberID)
	req, err := http.NewRequest(http.MethodPost, url, bytes.NewReader(raw))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("meta respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Messages []struct {
			ID string `json:"id"`
		} `json:"messages"`
	}
	_ = json.Unmarshal(data, &out)
	if len(out.Messages) > 0 {
		return out.Messages[0].ID, nil
	}
	return "", nil
}
