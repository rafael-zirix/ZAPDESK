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

// esHTTP é o cliente HTTP usado nas chamadas do Embedded Signup.
var esHTTP = &http.Client{Timeout: 20 * time.Second}

// exchangeEmbeddedCode troca o `code` do popup da Meta por um token de acesso
// (de longa duração) da empresa. client_id/secret são do app da plataforma.
func exchangeEmbeddedCode(apiBase, appID, appSecret, code string) (string, error) {
	return exchangeCode(apiBase, appID, appSecret, code, "")
}

// exchangeCode troca o código por token. O `redirectURI` distingue dois fluxos da
// Meta que parecem iguais: o Embedded Signup do WhatsApp devolve um código
// especial, trocado SEM redirect_uri; já o Login para Empresas pelo SDK devolve
// um código de OAuth comum, e a Meta exige o MESMO redirect_uri que o diálogo
// registrou (a URL da página) — sem ele responde 36008.
func exchangeCode(apiBase, appID, appSecret, code, redirectURI string) (string, error) {
	u := fmt.Sprintf("%s/oauth/access_token?client_id=%s&client_secret=%s&code=%s",
		apiBase, url.QueryEscape(appID), url.QueryEscape(appSecret), url.QueryEscape(code))
	if redirectURI != "" {
		u += "&redirect_uri=" + url.QueryEscape(redirectURI)
	}
	resp, err := esHTTP.Get(u)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("meta oauth respondeu %d: %s", resp.StatusCode, string(data))
	}
	var out struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return "", err
	}
	if out.AccessToken == "" {
		return "", fmt.Errorf("meta oauth não devolveu token")
	}
	return out.AccessToken, nil
}

// setPhoneWebhook aponta o webhook DAQUELE NÚMERO para cá, gravando na Meta.
//
// Por que existe: registrar o número na Cloud API resolve o ENVIO; o RECEBIMENTO
// depende de a Meta saber para onde mandar as mensagens. Sem isto o cliente teria
// de entrar no painel da Meta e preencher Callback URL e Verify Token à mão — e,
// esquecendo, ficaria com metade do produto (envia, não recebe).
//
// A Meta aceita um override POR NÚMERO, que PREVALECE sobre o webhook do app.
// Isso importa por dois motivos: o app do cliente pode já apontar para outro
// lugar, e continua apontando para os OUTROS números dele; e um app nosso com
// vários clientes não precisa de um webhook por cliente.
//
// Exige `whatsapp_business_management` no token. Token sem essa permissão falha
// aqui — daí o chamador tratar como best-effort e AVISAR, em vez de abortar a
// conexão: o cliente ainda pode configurar pelo painel da Meta.
func setPhoneWebhook(apiBase, phoneNumberID, token, callbackURL, verifyToken string) error {
	body, _ := json.Marshal(map[string]any{
		"webhook_configuration": map[string]string{
			"override_callback_uri": callbackURL,
			"verify_token":          verifyToken,
		},
	})
	req, err := http.NewRequest(http.MethodPost,
		fmt.Sprintf("%s/%s", apiBase, phoneNumberID), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := esHTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("meta recusou o webhook do número (%d): %s", resp.StatusCode, string(data))
	}
	return nil
}

// subscribeApp assina o app da plataforma nos webhooks da WABA (para receber as
// mensagens do número recém-conectado). Best-effort.
func subscribeApp(apiBase, wabaID, token string) error {
	u := fmt.Sprintf("%s/%s/subscribed_apps", apiBase, wabaID)
	req, err := http.NewRequest(http.MethodPost, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := esHTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("meta subscribe respondeu %d: %s", resp.StatusCode, string(data))
	}
	return nil
}
