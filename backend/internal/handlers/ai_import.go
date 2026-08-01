package handlers

import (
	"fmt"
	"html"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/middleware"
)

var (
	reScriptStyle = regexp.MustCompile(`(?is)<(script|style|noscript|template|svg)[^>]*>.*?</(script|style|noscript|template|svg)>`)
	reTag         = regexp.MustCompile(`(?s)<[^>]+>`)
	reTitle       = regexp.MustCompile(`(?is)<title[^>]*>(.*?)</title>`)
	reWS          = regexp.MustCompile(`[\s\x{00a0}]+`)
)

// siteClient busca páginas para importar (timeout curto; bloqueia redirect p/
// rede interna — SSRF básico, já que a ação é do admin da empresa).
var siteClient = &http.Client{
	Timeout: 12 * time.Second,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return fmt.Errorf("muitos redirecionamentos")
		}
		if isBlockedHost(req.URL.Hostname()) {
			return fmt.Errorf("redirecionamento para rede interna bloqueado")
		}
		return nil
	},
}

// ImportURL busca uma página, extrai o texto limpo e o cadastra como um item da
// base de conhecimento (respeitando o teto de caracteres). Se já existir um item
// com o mesmo título (mesmo site), atualiza-o em vez de duplicar.
func (h *AIHandler) ImportURL(c *gin.Context) {
	var req struct {
		URL string `json:"url" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Informe a URL do site", err.Error())
		return
	}
	raw := strings.TrimSpace(req.URL)
	if !strings.HasPrefix(raw, "http://") && !strings.HasPrefix(raw, "https://") {
		raw = "https://" + raw
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "URL inválida", nil)
		return
	}
	if isBlockedHost(u.Hostname()) {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Endereço não permitido (rede interna)", nil)
		return
	}

	reqHTTP, _ := http.NewRequest(http.MethodGet, raw, nil)
	// UA de navegador: muitos sites respondem 403 ao User-Agent padrão do Go.
	reqHTTP.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36")
	reqHTTP.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
	reqHTTP.Header.Set("Accept-Language", "pt-BR,pt;q=0.9,en;q=0.8")
	resp, err := siteClient.Do(reqHTTP)
	if err != nil {
		RespondError(c, http.StatusBadGateway, ErrInternal, "Não consegui acessar o site. Confira o endereço.", nil)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		RespondError(c, http.StatusBadGateway, ErrInternal, fmt.Sprintf("O site respondeu %d.", resp.StatusCode), nil)
		return
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 3<<20)) // 3 MB
	title, text := extractSiteText(string(body))
	text = strings.TrimSpace(text)
	if text == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Não encontrei texto legível nesse site.", nil)
		return
	}
	if title == "" {
		title = u.Hostname()
	}
	title = "Site: " + title

	accountID := middleware.AccountID(c)
	// Reimportar o mesmo site substitui (não duplica nem conta duas vezes no teto).
	existing := ""
	if items, e := h.support.AIRepo().ListContext(accountID); e == nil {
		for _, it := range items {
			if it.Title == title {
				existing = it.ID
				break
			}
		}
	}
	remaining := maxKBChars - h.kbUsed(accountID, existing)
	if remaining <= 0 {
		RespondError(c, http.StatusBadRequest, ErrValidation,
			fmt.Sprintf("A base já está no limite de %d caracteres. Remova algo antes de importar.", maxKBChars), nil)
		return
	}
	truncated := false
	if utf8.RuneCountInString(text) > remaining {
		text = strings.TrimSpace(string([]rune(text)[:remaining]))
		truncated = true
	}

	var saveErr error
	if existing != "" {
		_, saveErr = h.support.AIRepo().UpdateContext(accountID, existing, title, text)
	} else {
		_, saveErr = h.support.AIRepo().AddContext(accountID, title, text)
	}
	if saveErr != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Não foi possível salvar", saveErr.Error())
		return
	}

	n := utf8.RuneCountInString(text)
	msg := fmt.Sprintf("Site importado (%d caracteres).", n)
	if truncated {
		msg = fmt.Sprintf("Site importado, cortado em %d caracteres pelo limite da base.", remaining)
	}
	RespondSuccess(c, http.StatusCreated, msg, gin.H{"title": title, "chars": n})
}

// extractSiteText tira scripts/estilos/tags e devolve (título, texto limpo).
func extractSiteText(doc string) (string, string) {
	title := ""
	if m := reTitle.FindStringSubmatch(doc); m != nil {
		title = strings.TrimSpace(html.UnescapeString(reTag.ReplaceAllString(m[1], "")))
	}
	doc = reScriptStyle.ReplaceAllString(doc, " ")
	doc = reTag.ReplaceAllString(doc, " ")
	doc = html.UnescapeString(doc)
	doc = reWS.ReplaceAllString(doc, " ")
	return title, strings.TrimSpace(doc)
}

// isBlockedHost barra localhost / IPs de rede interna / metadados (SSRF básico).
func isBlockedHost(host string) bool {
	host = strings.ToLower(strings.Trim(host, "[]"))
	if host == "" || host == "localhost" || strings.HasSuffix(host, ".localhost") || host == "metadata" {
		return true
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified()
	}
	return false
}
