package services

import (
	"bytes"
	"encoding/json"
	"errors"
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

// ErrPINIncorreto: o número já tem PIN de verificação em duas etapas e o que
// mandamos não é ele. Só o dono resolve — informando o PIN certo ou zerando em
// WhatsApp Manager › Configurações › Verificação em duas etapas.
var ErrPINIncorreto = errors.New("PIN da verificação em duas etapas incorreto")

// RegisterPhone LIGA o número na Cloud API.
//
// Sem esta chamada o número existe no WABA, autentica, aceita ser conectado — e
// recusa todo envio com "(#133010) Account not registered". Verificar o número no
// Business Manager NÃO registra: são coisas diferentes, e a segunda só acontece
// por este endpoint.
//
// O pin vira o PIN de verificação em duas etapas do número. Se já houver um
// definido, tem de ser o mesmo, senão a Meta devolve 133005.
//
// É idempotente: registrar um número já registrado devolve sucesso.
func (c *MetaClient) RegisterPhone(pin string) error {
	raw, _ := json.Marshal(map[string]any{"messaging_product": "whatsapp", "pin": pin})
	req, err := http.NewRequest(http.MethodPost,
		fmt.Sprintf("%s/%s/register", c.apiBase, c.phoneNumberID), bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode < 300 {
		return nil
	}
	var e struct {
		Error struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	_ = json.Unmarshal(data, &e)
	switch e.Error.Code {
	case 133005:
		return ErrPINIncorreto
	// 133010 aqui significa que a conta ainda está sendo provisionada do lado da
	// Meta; costuma passar sozinho em alguns minutos
	case 133010:
		return fmt.Errorf("a Meta ainda não liberou este número para registro; tente de novo em alguns minutos")
	}
	return fmt.Errorf("meta respondeu %d: %s", resp.StatusCode, string(data))
}

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
// Enabled diz se a empresa quer vê-lo na barra de mensagens prontas (preferência
// local, fora da Meta); default true.
type TemplateInfo struct {
	Name     string `json:"name"`
	Language string `json:"language"`
	Status   string `json:"status"`
	Category string `json:"category"`
	BodyText string `json:"body_text"`
	Enabled  bool   `json:"enabled"`
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

// CreateTemplate cria um modelo de mensagem na WABA (vai para aprovação da Meta).
// Devolve o status inicial (normalmente PENDING) ou um erro da Meta.
func (c *MetaClient) CreateTemplate(wabaID, name, language, category, body string) (string, error) {
	payload := map[string]any{
		"name":     name,
		"language": language,
		"category": category,
		"components": []any{
			map[string]any{"type": "BODY", "text": body},
		},
	}
	raw, _ := json.Marshal(payload)
	u := fmt.Sprintf("%s/%s/message_templates", c.apiBase, wabaID)
	req, err := http.NewRequest(http.MethodPost, u, bytes.NewReader(raw))
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
		Status string `json:"status"`
	}
	_ = json.Unmarshal(data, &out)
	return out.Status, nil
}

// CreateAuthTemplate cria um template de AUTENTICAÇÃO (OTP) com botão "copiar
// código". O corpo é padronizado pela Meta (não mandamos texto); passamos só a
// recomendação de segurança e a validade. Devolve o status (normalmente PENDING).
func (c *MetaClient) CreateAuthTemplate(wabaID, name, language string, codeExpirationMinutes int) (string, error) {
	if language == "" {
		language = "pt_BR"
	}
	if codeExpirationMinutes <= 0 {
		codeExpirationMinutes = 10
	}
	payload := map[string]any{
		"name":     name,
		"language": language,
		"category": "AUTHENTICATION",
		"components": []any{
			map[string]any{"type": "BODY", "add_security_recommendation": true},
			map[string]any{"type": "FOOTER", "code_expiration_minutes": codeExpirationMinutes},
			map[string]any{"type": "BUTTONS", "buttons": []any{
				map[string]any{"type": "OTP", "otp_type": "COPY_CODE"},
			}},
		},
	}
	raw, _ := json.Marshal(payload)
	u := fmt.Sprintf("%s/%s/message_templates", c.apiBase, wabaID)
	req, err := http.NewRequest(http.MethodPost, u, bytes.NewReader(raw))
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
		Status string `json:"status"`
	}
	_ = json.Unmarshal(data, &out)
	return out.Status, nil
}

// SendAuthTemplate envia um template de autenticação com o código. O código vai
// no parâmetro do corpo E no botão "copiar código" (sub_type url, index 0).
func (c *MetaClient) SendAuthTemplate(to, name, lang, code string) (string, error) {
	if lang == "" {
		lang = "pt_BR"
	}
	return c.postMessage(map[string]any{
		"messaging_product": "whatsapp", "to": to, "type": "template",
		"template": map[string]any{
			"name":     name,
			"language": map[string]string{"code": lang},
			"components": []any{
				map[string]any{"type": "body", "parameters": []any{
					map[string]any{"type": "text", "text": code},
				}},
				map[string]any{"type": "button", "sub_type": "url", "index": "0", "parameters": []any{
					map[string]any{"type": "text", "text": code},
				}},
			},
		},
	})
}

// ConversationAnalytics devolve o total de conversas e o custo (na moeda da
// conta) da WABA no período [start, end] em unix. Best-effort: a Meta pode não
// expor o custo dependendo da versão/permissão do token.
func (c *MetaClient) ConversationAnalytics(wabaID string, start, end int64) (int, float64, error) {
	u := fmt.Sprintf("%s/%s?fields=conversation_analytics.start(%d).end(%d).granularity(DAILY)&access_token=%s",
		c.apiBase, wabaID, start, end, url.QueryEscape(c.token))
	resp, err := c.http.Get(u)
	if err != nil {
		return 0, 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return 0, 0, fmt.Errorf("meta analytics %d: %s", resp.StatusCode, string(data))
	}
	var raw struct {
		ConversationAnalytics struct {
			Data []struct {
				DataPoints []struct {
					Conversation int     `json:"conversation"`
					Cost         float64 `json:"cost"`
				} `json:"data_points"`
			} `json:"data"`
		} `json:"conversation_analytics"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return 0, 0, err
	}
	var convs int
	var cost float64
	for _, d := range raw.ConversationAnalytics.Data {
		for _, p := range d.DataPoints {
			convs += p.Conversation
			cost += p.Cost
		}
	}
	return convs, cost, nil
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

// postMessage envia um payload já montado ao endpoint de mensagens e devolve o wamid.
func (c *MetaClient) postMessage(body map[string]any) (string, error) {
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

// SendLocation envia uma localização (pino no mapa).
func (c *MetaClient) SendLocation(to string, lat, lng float64, name, address string) (string, error) {
	loc := map[string]any{"latitude": lat, "longitude": lng}
	if name != "" {
		loc["name"] = name
	}
	if address != "" {
		loc["address"] = address
	}
	return c.postMessage(map[string]any{
		"messaging_product": "whatsapp", "to": to, "type": "location", "location": loc,
	})
}

// SendContact envia um cartão de contato SALVÁVEL (nome + telefone). O phone
// chega só com dígitos (normalizado): exibe em formato internacional (+55…) e
// manda o wa_id, para o WhatsApp mostrar o cartão com opção de salvar/conversar.
func (c *MetaClient) SendContact(to, name, phone string) (string, error) {
	contact := map[string]any{
		"name": map[string]any{"formatted_name": name, "first_name": name},
		"phones": []map[string]any{
			{"phone": "+" + phone, "type": "CELL", "wa_id": phone},
		},
	}
	return c.postMessage(map[string]any{
		"messaging_product": "whatsapp", "to": to, "type": "contacts", "contacts": []any{contact},
	})
}

// InteractiveButton é um botão de resposta rápida (reply). Título ≤ 20 chars.
type InteractiveButton struct {
	ID    string
	Title string
}

// SendButtons envia uma mensagem com até 3 botões de resposta rápida. Só funciona
// DENTRO da janela de 24h (mensagem de sessão) — fora dela, a Meta rejeita.
func (c *MetaClient) SendButtons(to, body string, buttons []InteractiveButton) (string, error) {
	btns := make([]map[string]any, 0, len(buttons))
	for _, b := range buttons {
		btns = append(btns, map[string]any{
			"type":  "reply",
			"reply": map[string]string{"id": b.ID, "title": b.Title},
		})
	}
	return c.postMessage(map[string]any{
		"messaging_product": "whatsapp", "to": to, "type": "interactive",
		"interactive": map[string]any{
			"type":   "button",
			"body":   map[string]string{"text": body},
			"action": map[string]any{"buttons": btns},
		},
	})
}

// ListRow é uma linha do menu de lista. Título ≤ 24, descrição ≤ 72.
type ListRow struct {
	ID          string
	Title       string
	Description string
}

// SendList envia um menu de lista (até 10 linhas). buttonLabel é o texto do botão
// que abre a lista (≤ 20). Só funciona DENTRO da janela de 24h.
func (c *MetaClient) SendList(to, body, buttonLabel, sectionTitle string, rows []ListRow) (string, error) {
	rws := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		row := map[string]any{"id": r.ID, "title": r.Title}
		if r.Description != "" {
			row["description"] = r.Description
		}
		rws = append(rws, row)
	}
	if sectionTitle == "" {
		sectionTitle = "Opções"
	}
	if buttonLabel == "" {
		buttonLabel = "Ver opções"
	}
	return c.postMessage(map[string]any{
		"messaging_product": "whatsapp", "to": to, "type": "interactive",
		"interactive": map[string]any{
			"type": "list",
			"body": map[string]string{"text": body},
			"action": map[string]any{
				"button":   buttonLabel,
				"sections": []map[string]any{{"title": sectionTitle, "rows": rws}},
			},
		},
	})
}

// MarkRead marca uma mensagem RECEBIDA como lida (✓✓ azul p/ o cliente). Se
// typing=true, também mostra o indicador "digitando…" (some em ~25s ou quando você
// envia algo). Precisa de uma mensagem recebida dentro da janela de 24h.
func (c *MetaClient) MarkRead(messageID string, typing bool) error {
	body := map[string]any{
		"messaging_product": "whatsapp",
		"status":            "read",
		"message_id":        messageID,
	}
	if typing {
		body["typing_indicator"] = map[string]string{"type": "text"}
	}
	raw, _ := json.Marshal(body)
	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/%s/messages", c.apiBase, c.phoneNumberID), bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("meta read respondeu %d: %s", resp.StatusCode, string(data))
	}
	return nil
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
