package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
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

// TemplateInfo é um template de mensagem aprovado (com prévia do corpo).
type TemplateInfo struct {
	Name     string `json:"name"`
	Language string `json:"language"`
	Status   string `json:"status"`
	Category string `json:"category"`
	BodyText string `json:"body_text"`
}

// ListTemplates devolve os templates da WABA (só os APPROVED).
func (c *MetaClient) ListTemplates(wabaID string) ([]TemplateInfo, error) {
	u := fmt.Sprintf("%s/%s/message_templates?limit=200&access_token=%s", c.apiBase, wabaID, url.QueryEscape(c.token))
	resp, err := c.http.Get(u)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("meta respondeu %d: %s", resp.StatusCode, string(data))
	}
	var raw struct {
		Data []struct {
			Name       string `json:"name"`
			Language   string `json:"language"`
			Status     string `json:"status"`
			Category   string `json:"category"`
			Components []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"components"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	out := make([]TemplateInfo, 0, len(raw.Data))
	for _, t := range raw.Data {
		if t.Status != "APPROVED" {
			continue
		}
		body := ""
		for _, comp := range t.Components {
			if comp.Type == "BODY" {
				body = comp.Text
				break
			}
		}
		out = append(out, TemplateInfo{Name: t.Name, Language: t.Language, Status: t.Status, Category: t.Category, BodyText: body})
	}
	return out, nil
}

// SendTemplate envia uma mensagem de template (fura a janela de 24h).
func (c *MetaClient) SendTemplate(to, name, lang string) (string, error) {
	if lang == "" {
		lang = "pt_BR"
	}
	body := map[string]any{
		"messaging_product": "whatsapp",
		"to":                to,
		"type":              "template",
		"template": map[string]any{
			"name":     name,
			"language": map[string]string{"code": lang},
		},
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/%s/messages", c.apiBase, c.phoneNumberID), bytes.NewReader(raw))
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
