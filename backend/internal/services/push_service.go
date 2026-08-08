package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// PushService envia notificações para os aparelhos dos atendentes pelo FCM
// (HTTP v1). A autenticação é a padrão do Google: monta-se um JWT assinado com
// a chave da service account e troca-se por um access token de 1h.
//
// Não usamos o SDK do Firebase de propósito — ele arrastaria dezenas de
// dependências para fazer exatamente estas duas chamadas HTTP.
//
// Sem credencial configurada o serviço fica INERTE: [Enabled] devolve false e
// todo envio é ignorado em silêncio. O resto do sistema funciona igual.
type PushService struct {
	client   *http.Client
	email    string
	key      any    // *rsa.PrivateKey da service account
	project  string
	enabled  bool
	onFailed func(token string) // apaga tokens que o FCM diz não existirem mais

	mu      sync.Mutex
	token   string
	expires time.Time
}

// serviceAccount é o recorte do JSON que o Google entrega ao criar a chave.
type serviceAccount struct {
	Type        string `json:"type"`
	ProjectID   string `json:"project_id"`
	PrivateKey  string `json:"private_key"`
	ClientEmail string `json:"client_email"`
}

// NewPushService lê a service account do caminho informado. Caminho vazio (ou
// arquivo ilegível) devolve um serviço desligado, sem erro: notificação é
// recurso opcional e não pode impedir a API de subir.
func NewPushService(credentialsPath string) *PushService {
	s := &PushService{client: &http.Client{Timeout: 15 * time.Second}}
	if strings.TrimSpace(credentialsPath) == "" {
		return s
	}
	raw, err := os.ReadFile(credentialsPath)
	if err != nil {
		slog.Warn("push: credencial do Firebase não pôde ser lida — notificações desligadas", "erro", err)
		return s
	}
	var sa serviceAccount
	if err := json.Unmarshal(raw, &sa); err != nil || sa.ClientEmail == "" || sa.PrivateKey == "" {
		slog.Warn("push: credencial do Firebase inválida — notificações desligadas")
		return s
	}
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(sa.PrivateKey))
	if err != nil {
		slog.Warn("push: chave privada da service account inválida", "erro", err)
		return s
	}
	s.email, s.key, s.project, s.enabled = sa.ClientEmail, key, sa.ProjectID, true
	slog.Info("push: notificações ligadas", "projeto", sa.ProjectID)
	return s
}

// WithTokenCleanup registra o que fazer quando um token morre (app desinstalado).
func (s *PushService) WithTokenCleanup(f func(token string)) *PushService {
	s.onFailed = f
	return s
}

func (s *PushService) Enabled() bool { return s != nil && s.enabled }

// Send dispara a mesma notificação para vários aparelhos. Best-effort: erro de
// um token não interrompe os demais, e nada disso pode travar o webhook.
func (s *PushService) Send(tokens []string, title, body string, data map[string]string) {
	if !s.Enabled() || len(tokens) == 0 {
		return
	}
	access, err := s.accessToken()
	if err != nil {
		slog.Error("push: falha ao obter access token", "erro", err)
		return
	}
	for _, t := range tokens {
		if err := s.sendOne(access, t, title, body, data); err != nil {
			// Token morto: o FCM devolve 404/UNREGISTERED. Limpa para não
			// tentar de novo a cada mensagem.
			if errors.Is(err, errTokenMorto) {
				if s.onFailed != nil {
					s.onFailed(t)
				}
				continue
			}
			slog.Warn("push: envio falhou", "erro", err)
		}
	}
}

var errTokenMorto = errors.New("token não registrado")

func (s *PushService) sendOne(access, token, title, body string, data map[string]string) error {
	payload := map[string]any{
		"message": map[string]any{
			"token": token,
			"notification": map[string]string{
				"title": title,
				"body":  body,
			},
			"data": data,
			"android": map[string]any{
				"priority": "high",
				"notification": map[string]any{
					"channel_id": "mensagens", // o canal que o app cria no Android
					"sound":      "default",
				},
			},
			"apns": map[string]any{
				"payload": map[string]any{
					"aps": map[string]any{"sound": "default"},
				},
			},
		},
	}
	buf, _ := json.Marshal(payload)
	endpoint := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", s.project)
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+access)
	req.Header.Set("Content-Type", "application/json")
	res, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode == http.StatusOK {
		return nil
	}
	corpo, _ := io.ReadAll(io.LimitReader(res.Body, 2048))
	if res.StatusCode == http.StatusNotFound || strings.Contains(string(corpo), "UNREGISTERED") {
		return errTokenMorto
	}
	return fmt.Errorf("fcm %d: %s", res.StatusCode, string(corpo))
}

// accessToken devolve um token OAuth2 válido, renovando quando falta pouco para
// vencer (o token dura 1h; renovar a cada mensagem seria desperdício).
func (s *PushService) accessToken() (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.token != "" && time.Now().Before(s.expires.Add(-2*time.Minute)) {
		return s.token, nil
	}
	agora := time.Now()
	claims := jwt.MapClaims{
		"iss":   s.email,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   "https://oauth2.googleapis.com/token",
		"iat":   agora.Unix(),
		"exp":   agora.Add(time.Hour).Unix(),
	}
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(s.key)
	if err != nil {
		return "", err
	}
	form := url.Values{
		"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"},
		"assertion":  {assertion},
	}
	res, err := s.client.PostForm("https://oauth2.googleapis.com/token", form)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	corpo, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("oauth %d: %s", res.StatusCode, string(corpo))
	}
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.Unmarshal(corpo, &out); err != nil || out.AccessToken == "" {
		return "", errors.New("resposta de token inválida")
	}
	s.token = out.AccessToken
	s.expires = agora.Add(time.Duration(out.ExpiresIn) * time.Second)
	return s.token, nil
}
