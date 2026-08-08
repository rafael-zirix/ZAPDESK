package services

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"
)

// Conexão do Instagram pelo popup da Meta ("Continuar com Facebook"), em vez de
// o cliente copiar IG User ID, ID da Página e token do Graph API Explorer.
//
// Isso não é detalhe de conforto: o formulário manual funciona para nós e trava
// qualquer cliente — ninguém vai gerar token de Página à mão. A senha do
// Instagram nunca passa por aqui; quem autentica é a Meta, no domínio dela, e o
// que volta é um `code` de uso único que trocamos por token no servidor.
//
// O fluxo tem um degrau a mais que o do WhatsApp: o popup devolve o usuário, não
// a Página. Uma conta do Facebook pode administrar várias Páginas, e cada Página
// pode ter (ou não) uma conta profissional do Instagram vinculada. Então:
// descobrimos as Páginas, e só quando há mais de uma candidata é que perguntamos.

// pendingLogin guarda as candidatas de um popup enquanto o usuário escolhe.
//
// Existe porque o `code` da Meta é de USO ÚNICO: se guardássemos só o code para
// trocar de novo depois da escolha, a segunda troca falharia e o usuário teria de
// refazer o popup. Os tokens ficam no servidor — a lista que vai à tela leva
// apenas nome, @ e ids.
type pendingLogin struct {
	accountID string
	criadoEm  time.Time
	paginas   []IGCandidate
}

// IGCandidate é uma Página com conta profissional do Instagram vinculada.
type IGCandidate struct {
	PageID    string `json:"page_id"`
	PageName  string `json:"page_name"`
	IGUserID  string `json:"ig_user_id"`
	Username  string `json:"username"`
	pageToken string // nunca sai daqui
}

const pendingLoginTTL = 10 * time.Minute

var (
	pendingMu     sync.Mutex
	pendingByHash = map[string]pendingLogin{}
)

// WithFacebookLogin habilita a conexão via popup. Vazios = desligado, e a tela
// mostra só o formulário manual.
func (s *InstagramService) WithFacebookLogin(appID, appSecret, configID, graphVer string) *InstagramService {
	s.fbAppID, s.fbSecret, s.fbConfig, s.fbGraph = appID, appSecret, configID, graphVer
	return s
}

// LoginConfig devolve o que o front precisa para abrir o popup, e se está ligado.
func (s *InstagramService) LoginConfig() (appID, configID, graphVer string, enabled bool) {
	enabled = s.fbAppID != "" && s.fbSecret != "" && s.fbConfig != "" && s.cipher != nil
	return s.fbAppID, s.fbConfig, s.fbGraph, enabled
}

// ErrIGChooseAccount indica que há mais de uma Página candidata: a tela precisa
// perguntar qual, e confirmar em ConnectChosen com o mesmo `sessao`.
var ErrIGChooseAccount = errors.New("escolha a conta do Instagram")

// ConnectViaLogin troca o code do popup por token, descobre as Páginas com
// Instagram vinculado e conecta quando não há dúvida.
//
// Devolve (conta conectada, nil) no caminho feliz; (candidatas, ErrIGChooseAccount)
// quando há mais de uma Página — aí a tela chama ConnectChosen.
func (s *InstagramService) ConnectViaLogin(accountID, code string) (string, []IGCandidate, error) {
	if s.fbAppID == "" || s.fbSecret == "" {
		return "", nil, errors.New("conexão pela Meta não está configurada")
	}
	if strings.TrimSpace(code) == "" {
		return "", nil, errors.New("o popup da Meta não devolveu autorização")
	}
	userToken, err := exchangeEmbeddedCode(s.apiBase, s.fbAppID, s.fbSecret, code)
	if err != nil {
		return "", nil, err
	}
	paginas, err := fetchIGPages(s.apiBase, userToken)
	if err != nil {
		return "", nil, err
	}
	switch len(paginas) {
	case 0:
		// Erro comum e específico: vale explicar em vez de dizer "falhou".
		return "", nil, errors.New("nenhuma Página com conta profissional do Instagram vinculada. " +
			"Confira no Instagram se o perfil é Profissional e está ligado a uma Página do Facebook")
	case 1:
		return "", nil, s.conectar(accountID, paginas[0])
	}
	sessao := novaSessaoLogin(accountID, paginas)
	return sessao, paginas, ErrIGChooseAccount
}

// ConnectChosen conclui a conexão quando havia mais de uma Página.
func (s *InstagramService) ConnectChosen(accountID, sessao, pageID string) error {
	pendingMu.Lock()
	p, ok := pendingByHash[sessao]
	if ok {
		delete(pendingByHash, sessao)
	}
	pendingMu.Unlock()
	if !ok || p.accountID != accountID || time.Since(p.criadoEm) > pendingLoginTTL {
		return errors.New("a escolha expirou — conecte pela Meta de novo")
	}
	for _, c := range p.paginas {
		if c.PageID == pageID {
			return s.conectar(accountID, c)
		}
	}
	return errors.New("página não encontrada na escolha")
}

// conectar salva o token cifrado. Quem assina a Página nos webhooks é o Connect,
// para o caminho manual e o do popup terem exatamente o mesmo efeito.
func (s *InstagramService) conectar(accountID string, c IGCandidate) error {
	return s.Connect(accountID, c.IGUserID, c.PageID, c.Username, c.pageToken)
}

// Reactivate religa uma conta desconectada e reassina a Página nos webhooks.
func (s *InstagramService) Reactivate(accountID, id string) error {
	acc, err := s.repo.Reactivate(accountID, id)
	if err != nil {
		return err
	}
	if acc == nil {
		return ErrInstagramNotConnected
	}
	token, err := s.cipher.Decrypt(acc.TokenEnc)
	if err != nil {
		return err
	}
	return subscribePage(s.apiBase, acc.PageID, token)
}

// Resubscribe reassina a Página nos webhooks usando o token já guardado. Serve
// para as contas conectadas antes de o Connect passar a assinar sozinho.
func (s *InstagramService) Resubscribe(accountID string) error {
	token, _, err := s.tokenFor(accountID)
	if err != nil {
		return err
	}
	acc, err := s.repo.ByAccountID(accountID)
	if err != nil || acc == nil {
		return ErrInstagramNotConnected
	}
	return subscribePage(s.apiBase, acc.PageID, token)
}

func novaSessaoLogin(accountID string, paginas []IGCandidate) string {
	sessao := fmt.Sprintf("%s-%d", accountID, time.Now().UnixNano())
	pendingMu.Lock()
	defer pendingMu.Unlock()
	for k, v := range pendingByHash { // limpeza preguiçosa
		if time.Since(v.criadoEm) > pendingLoginTTL {
			delete(pendingByHash, k)
		}
	}
	pendingByHash[sessao] = pendingLogin{accountID: accountID, criadoEm: time.Now(), paginas: paginas}
	return sessao
}

// fetchIGPages lista as Páginas do usuário que têm Instagram profissional ligado.
func fetchIGPages(apiBase, userToken string) ([]IGCandidate, error) {
	u := apiBase + "/me/accounts?fields=id,name,access_token,instagram_business_account{id,username}&limit=100"
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+userToken)
	resp, err := esHTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("meta respondeu %d ao listar as Páginas: %s", resp.StatusCode, string(data))
	}
	var out struct {
		Data []struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			AccessToken string `json:"access_token"`
			IG          struct {
				ID       string `json:"id"`
				Username string `json:"username"`
			} `json:"instagram_business_account"`
		} `json:"data"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return nil, err
	}
	var cands []IGCandidate
	for _, p := range out.Data {
		if p.IG.ID == "" || p.AccessToken == "" {
			continue // Página sem Instagram vinculado não serve
		}
		cands = append(cands, IGCandidate{
			PageID: p.ID, PageName: p.Name,
			IGUserID: p.IG.ID, Username: p.IG.Username, pageToken: p.AccessToken,
		})
	}
	return cands, nil
}

// checkPageToken confere que o token é MESMO da Página informada.
//
// Existe porque o formulário manual aceita qualquer string, e um token de
// usuário (o que o Graph API Explorer entrega por padrão) salva sem reclamar e
// só falha depois, na hora de assinar — a conta fica "conectada" sem receber
// nada. Melhor recusar na entrada, dizendo o que veio no lugar.
func checkPageToken(apiBase, pageID, token string) error {
	req, err := http.NewRequest(http.MethodGet, apiBase+"/me?fields=id,name", nil)
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
		return fmt.Errorf("a Meta recusou o token: %s", metaErrorMessage(data))
	}
	var me struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := json.Unmarshal(data, &me); err != nil {
		return err
	}
	if me.ID != pageID {
		return fmt.Errorf("esse token não é da Página %s — ele pertence a \"%s\" (%s). "+
			"No Graph API Explorer, rode GET /me/accounts?fields=id,name,access_token,"+
			"instagram_business_account{id,username} e copie o access_token DA PÁGINA",
			pageID, me.Name, me.ID)
	}
	return nil
}

// subscribePage assina o nosso app nos eventos da Página. Sem isto a Meta não
// entrega nem o Direct (`messages`) nem os formulários de anúncio (`leadgen`).
func subscribePage(apiBase, pageID, pageToken string) error {
	u := fmt.Sprintf("%s/%s/subscribed_apps?subscribed_fields=messages,messaging_postbacks,leadgen", apiBase, pageID)
	req, err := http.NewRequest(http.MethodPost, u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+pageToken)
	resp, err := esHTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("meta subscribe da Página respondeu %d: %s", resp.StatusCode, string(data))
	}
	return nil
}
