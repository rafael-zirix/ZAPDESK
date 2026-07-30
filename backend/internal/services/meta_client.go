package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/textproto"
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

// --- Mídia (foto/documento/áudio/vídeo) ---

// UploadMedia envia o arquivo para a Meta e devolve o media_id.
func (c *MetaClient) UploadMedia(data []byte, filename, mimeType string) (string, error) {
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	_ = w.WriteField("messaging_product", "whatsapp")
	h := make(textproto.MIMEHeader)
	h.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename=%q`, filename))
	h.Set("Content-Type", mimeType)
	part, err := w.CreatePart(h)
	if err != nil {
		return "", err
	}
	if _, err := part.Write(data); err != nil {
		return "", err
	}
	_ = w.Close()

	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/%s/media", c.apiBase, c.phoneNumberID), &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("meta upload respondeu %d: %s", resp.StatusCode, string(b))
	}
	var out struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(b, &out)
	return out.ID, nil
}

// SendMedia envia uma mensagem com mídia (por media_id). kind = image|document|audio|video.
func (c *MetaClient) SendMedia(to, kind, mediaID, filename, caption string) (string, error) {
	media := map[string]any{"id": mediaID}
	if caption != "" && (kind == "image" || kind == "document" || kind == "video") {
		media["caption"] = caption
	}
	if kind == "document" && filename != "" {
		media["filename"] = filename
	}
	body := map[string]any{
		"messaging_product": "whatsapp",
		"to":                to,
		"type":              kind,
		kind:                media,
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

// DownloadMedia baixa uma mídia recebida (resolve a URL pelo media_id e busca os
// bytes). Devolve os bytes e o mime type.
func (c *MetaClient) DownloadMedia(mediaID string) ([]byte, string, error) {
	// 1) resolve a URL temporária
	req, _ := http.NewRequest(http.MethodGet, fmt.Sprintf("%s/%s", c.apiBase, mediaID), nil)
	req.Header.Set("Authorization", "Bearer "+c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	var meta struct {
		URL      string `json:"url"`
		MimeType string `json:"mime_type"`
	}
	b, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, "", fmt.Errorf("meta media respondeu %d: %s", resp.StatusCode, string(b))
	}
	_ = json.Unmarshal(b, &meta)
	if meta.URL == "" {
		return nil, "", fmt.Errorf("media sem url")
	}
	// 2) baixa os bytes (precisa do token)
	req2, _ := http.NewRequest(http.MethodGet, meta.URL, nil)
	req2.Header.Set("Authorization", "Bearer "+c.token)
	resp2, err := c.http.Do(req2)
	if err != nil {
		return nil, "", err
	}
	defer resp2.Body.Close()
	data, err := io.ReadAll(resp2.Body)
	if err != nil {
		return nil, "", err
	}
	if resp2.StatusCode >= 300 {
		return nil, "", fmt.Errorf("meta download respondeu %d", resp2.StatusCode)
	}
	return data, meta.MimeType, nil
}
