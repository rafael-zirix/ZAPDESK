package services

// Criação de MODELOS (templates) na Meta, completos: cabeçalho de texto ou
// IMAGEM, corpo com variáveis {{n}} + exemplos, rodapé e botões.
//
// Duas regras da Meta que fazem a criação falhar quando ignoradas:
//  1. corpo com {{n}} EXIGE exemplos (`example.body_text`), senão 132000/2388043;
//  2. cabeçalho de imagem EXIGE um "handle" de uma imagem de exemplo, obtido
//     pela Resumable Upload API (/{app_id}/uploads) — não aceita URL.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
)

// TemplateButton é um botão do modelo (resposta rápida, link ou telefone).
type TemplateButton struct {
	Type  string `json:"type"`  // QUICK_REPLY | URL | PHONE_NUMBER
	Text  string `json:"text"`  // rótulo (máx. 25 caracteres)
	URL   string `json:"url"`   // type=URL
	Phone string `json:"phone"` // type=PHONE_NUMBER
}

// TemplateSpec descreve o modelo a criar.
type TemplateSpec struct {
	Name         string           `json:"name"`
	Language     string           `json:"language"`
	Category     string           `json:"category"`      // MARKETING | UTILITY | AUTHENTICATION
	HeaderType   string           `json:"header_type"`   // "" | TEXT | IMAGE
	HeaderText   string           `json:"header_text"`   // header_type=TEXT
	HeaderHandle string           `json:"header_handle"` // header_type=IMAGE (do upload)
	Body         string           `json:"body"`
	BodyExamples []string         `json:"body_examples"` // um por variável {{n}}
	Footer       string           `json:"footer"`
	Buttons      []TemplateButton `json:"buttons"`
	// Para que o modelo serve AQUI ('chat' | 'campaign'). NÃO vai para a Meta:
	// fixa em que lista ele aparece, independente da categoria que a revisão
	// dela decidir (a Meta recategoriza quando quer).
	Usage string `json:"usage"`
}

var templateVarRe = regexp.MustCompile(`\{\{(\d+)\}\}`)

// CountTemplateVars devolve o maior índice de variável usado no texto.
func CountTemplateVars(text string) int {
	max := 0
	for _, m := range templateVarRe.FindAllStringSubmatch(text, -1) {
		var n int
		_, _ = fmt.Sscanf(m[1], "%d", &n)
		if n > max {
			max = n
		}
	}
	return max
}

// components monta os componentes do template no formato da Graph API.
func (s TemplateSpec) components() []any {
	comps := []any{}

	switch strings.ToUpper(s.HeaderType) {
	case "TEXT":
		h := map[string]any{"type": "HEADER", "format": "TEXT", "text": s.HeaderText}
		if n := CountTemplateVars(s.HeaderText); n > 0 {
			// Cabeçalho aceita no máximo 1 variável.
			h["example"] = map[string]any{"header_text": []string{"exemplo"}}
		}
		comps = append(comps, h)
	case "IMAGE":
		comps = append(comps, map[string]any{
			"type":    "HEADER",
			"format":  "IMAGE",
			"example": map[string]any{"header_handle": []string{s.HeaderHandle}},
		})
	}

	body := map[string]any{"type": "BODY", "text": s.Body}
	if n := CountTemplateVars(s.Body); n > 0 {
		ex := make([]string, n)
		for i := 0; i < n; i++ {
			if i < len(s.BodyExamples) && strings.TrimSpace(s.BodyExamples[i]) != "" {
				ex[i] = s.BodyExamples[i]
			} else {
				ex[i] = "exemplo"
			}
		}
		body["example"] = map[string]any{"body_text": [][]string{ex}}
	}
	comps = append(comps, body)

	if strings.TrimSpace(s.Footer) != "" {
		comps = append(comps, map[string]any{"type": "FOOTER", "text": s.Footer})
	}

	if len(s.Buttons) > 0 {
		btns := make([]any, 0, len(s.Buttons))
		for _, b := range s.Buttons {
			switch strings.ToUpper(b.Type) {
			case "URL":
				btns = append(btns, map[string]any{"type": "URL", "text": b.Text, "url": b.URL})
			case "PHONE_NUMBER":
				btns = append(btns, map[string]any{"type": "PHONE_NUMBER", "text": b.Text, "phone_number": b.Phone})
			default:
				btns = append(btns, map[string]any{"type": "QUICK_REPLY", "text": b.Text})
			}
		}
		comps = append(comps, map[string]any{"type": "BUTTONS", "buttons": btns})
	}
	return comps
}

// CreateTemplateFull cria o modelo na WABA com todos os componentes.
func (c *MetaClient) CreateTemplateFull(wabaID string, spec TemplateSpec) (string, error) {
	payload := map[string]any{
		"name":       spec.Name,
		"language":   spec.Language,
		"category":   spec.Category,
		"components": spec.components(),
	}
	raw, _ := json.Marshal(payload)
	req, err := http.NewRequest(http.MethodPost,
		fmt.Sprintf("%s/%s/message_templates", c.apiBase, wabaID), bytes.NewReader(raw))
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
		return "", fmt.Errorf("%s", metaErrorMessage(data))
	}
	var out struct {
		Status string `json:"status"`
	}
	_ = json.Unmarshal(data, &out)
	if out.Status == "" {
		out.Status = "PENDING"
	}
	return out.Status, nil
}

// UploadSampleImage sobe a imagem de EXEMPLO do cabeçalho pela Resumable Upload
// API e devolve o handle (o que a Meta aceita em example.header_handle).
//
// Passo 1: abre a sessão em /{app_id}/uploads (tamanho + tipo).
// Passo 2: envia os bytes na sessão com o header OAuth — a resposta traz "h".
func (c *MetaClient) UploadSampleImage(appID string, data []byte, mimeType string) (string, error) {
	if appID == "" {
		return "", fmt.Errorf("META_APP_ID não configurado — necessário para modelos com imagem")
	}
	if mimeType == "" {
		mimeType = "image/jpeg"
	}
	q := url.Values{}
	q.Set("file_length", fmt.Sprintf("%d", len(data)))
	q.Set("file_type", mimeType)
	q.Set("access_token", c.token)
	resp, err := c.http.Post(fmt.Sprintf("%s/%s/uploads?%s", c.apiBase, appID, q.Encode()), "application/json", nil)
	if err != nil {
		return "", err
	}
	body, _ := io.ReadAll(resp.Body)
	_ = resp.Body.Close()
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("%s", metaErrorMessage(body))
	}
	var session struct {
		ID string `json:"id"`
	}
	_ = json.Unmarshal(body, &session)
	if session.ID == "" {
		return "", fmt.Errorf("a Meta não devolveu a sessão de upload")
	}

	req, err := http.NewRequest(http.MethodPost, fmt.Sprintf("%s/%s", c.apiBase, session.ID), bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "OAuth "+c.token) // este passo NÃO usa Bearer
	req.Header.Set("file_offset", "0")
	req.Header.Set("Content-Type", mimeType)
	resp2, err := c.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp2.Body.Close()
	body2, _ := io.ReadAll(resp2.Body)
	if resp2.StatusCode >= 300 {
		return "", fmt.Errorf("%s", metaErrorMessage(body2))
	}
	var out struct {
		H string `json:"h"`
	}
	_ = json.Unmarshal(body2, &out)
	if out.H == "" {
		return "", fmt.Errorf("a Meta não devolveu o identificador da imagem")
	}
	return out.H, nil
}

// metaErrorMessage extrai a mensagem legível de um erro da Graph API.
func metaErrorMessage(raw []byte) string {
	var e struct {
		Error struct {
			Message      string `json:"message"`
			ErrorUserMsg string `json:"error_user_msg"`
		} `json:"error"`
	}
	if json.Unmarshal(raw, &e) == nil {
		if e.Error.ErrorUserMsg != "" {
			return e.Error.ErrorUserMsg
		}
		if e.Error.Message != "" {
			return e.Error.Message
		}
	}
	return string(raw)
}
