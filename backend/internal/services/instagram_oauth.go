package services

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
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
func (s *InstagramService) ConnectViaLogin(accountID, code, redirectURI string) (string, []IGCandidate, error) {
	if s.fbAppID == "" || s.fbSecret == "" {
		return "", nil, errors.New("conexão pela Meta não está configurada")
	}
	if strings.TrimSpace(code) == "" {
		return "", nil, errors.New("o popup da Meta não devolveu autorização")
	}
	// COM o redirect_uri: o diálogo é aberto por nós (ver zapFacebookLogin no
	// index.html), então o endereço é o mesmo dos dois lados — que é exatamente o
	// que o subcode 36008 exige. Sem ele só quando o front não mandar.
	userToken, err := exchangeCode(s.apiBase, s.fbAppID, s.fbSecret, code, redirectURI)
	if err != nil && redirectURI != "" {
		slog.Warn("Instagram login: troca com redirect_uri falhou, tentando sem", "erro", err)
		userToken, err = exchangeCode(s.apiBase, s.fbAppID, s.fbSecret, code, "")
	}
	if err != nil {
		slog.Warn("Instagram login: troca do code falhou", "erro", err)
		return "", nil, err
	}
	paginas, err := fetchIGPages(s.apiBase, userToken)
	if err != nil {
		slog.Warn("Instagram login: falha ao listar as Páginas", "erro", err)
		return "", nil, err
	}
	slog.Info("Instagram login: Páginas com Instagram encontradas", "qtd", len(paginas))
	switch len(paginas) {
	case 0:
		// Erro comum e específico: vale explicar em vez de dizer "falhou".
		return "", nil, errors.New("nenhuma Página com conta profissional do Instagram vinculada. " +
			"Confira no Instagram se o perfil é Profissional e está ligado a uma Página do Facebook")
	case 1:
		if err := s.conectar(accountID, paginas[0]); err != nil {
			slog.Warn("Instagram login: falha ao conectar", "erro", err, "page_id", paginas[0].PageID)
			return "", nil, err
		}
		return "", nil, nil
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
	return s.reassinar(acc.PageID, acc.IGUserID, token)
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
	return s.reassinar(acc.PageID, acc.IGUserID, token)
}

// reassinar refaz as assinaturas. Só as MENSAGENS decidem o veredito: leadgen e
// a tentativa no objeto do Instagram são acessórias, e reportá-las como falha
// fazia um reassinamento bem-sucedido aparecer em vermelho na tela.
func (s *InstagramService) reassinar(pageID, igUserID, token string) error {
	if err := subscribeLeadgen(s.apiBase, pageID, token); err != nil {
		slog.Warn("Instagram: sem leadgen", "erro", err, "page_id", pageID)
	}
	if err := subscribeIG(s.apiBase, igUserID, token); err != nil {
		slog.Warn("Instagram: objeto do Instagram recusou (esperado nesta variante)", "erro", err)
	}
	return subscribePage(s.apiBase, pageID, token)
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
// Existe porque o formulário manual aceita qualquer string: um token de usuário
// (o que o Graph API Explorer entrega por padrão) salvava sem reclamar e só
// falhava depois, na hora de assinar. E devolve o IG User ID REAL da Página —
// nunca o que veio na requisição, que é o que impede uma empresa de cadastrar o
// id do Instagram de outra e desviar as conversas dela.
func checkPageToken(apiBase, pageID, token string) (string, error) {
	req, err := http.NewRequest(http.MethodGet,
		fmt.Sprintf("%s/%s?fields=id,name,instagram_business_account{id,username}", apiBase, pageID), nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := esHTTP.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("a Meta recusou o token para esta Página: %s", metaErrorMessage(data))
	}
	var pag struct {
		ID   string `json:"id"`
		Name string `json:"name"`
		IG   struct {
			ID string `json:"id"`
		} `json:"instagram_business_account"`
	}
	if err := json.Unmarshal(data, &pag); err != nil {
		return "", err
	}
	if pag.ID != pageID {
		return "", fmt.Errorf("esse token não é da Página %s — ele responde por \"%s\" (%s)",
			pageID, pag.Name, pag.ID)
	}
	if pag.IG.ID == "" {
		return "", fmt.Errorf("a Página %s não tem conta profissional do Instagram vinculada", pageID)
	}
	return pag.IG.ID, nil
}

// logGrantedScopes registra as permissões que o token REALMENTE recebeu.
//
// Vale o custo de uma chamada: os erros da Meta para permissão faltando são
// enganosos (ora "user access token is required", ora "object does not exist"),
// e sem a lista a gente fica trocando de endpoint no escuro.
func logGrantedScopes(apiBase, token string) {
	req, err := http.NewRequest(http.MethodGet, apiBase+"/me/permissions", nil)
	if err != nil {
		return
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := esHTTP.Do(req)
	if err != nil {
		return
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	var out struct {
		Data []struct {
			Permission string `json:"permission"`
			Status     string `json:"status"`
		} `json:"data"`
	}
	if json.Unmarshal(data, &out) != nil {
		return
	}
	var ok, negadas []string
	for _, p := range out.Data {
		if p.Status == "granted" {
			ok = append(ok, p.Permission)
		} else {
			negadas = append(negadas, p.Permission)
		}
	}
	slog.Info("Instagram: permissões do token", "concedidas", strings.Join(ok, ","), "negadas", strings.Join(negadas, ","))
}

// subscribeIG assina o app nas MENSAGENS da conta do Instagram.
//
// Este é o objeto certo para o Direct: a assinatura vai na conta do Instagram,
// com o token da Página. Assinar a Página com `messages` devolve erro 102
// ("user access token is required"), que engana — a chamada não está errada de
// token, está errada de objeto.
func subscribeIG(apiBase, igUserID, pageToken string) error {
	u := fmt.Sprintf("%s/%s/subscribed_apps?subscribed_fields=messages,messaging_postbacks", apiBase, igUserID)
	return postSubscribe(u, pageToken)
}

// subscribePage assina as MENSAGENS da Página — é o que faz o Direct chegar.
//
// Separado do leadgen de propósito: a Meta reprova a chamada INTEIRA quando um
// dos campos pedidos não tem permissão, então juntar os dois fazia o `leadgen`
// (que exige leads_retrieval) derrubar as mensagens junto.
func subscribePage(apiBase, pageID, pageToken string) error {
	u := fmt.Sprintf("%s/%s/subscribed_apps?subscribed_fields=messages,messaging_postbacks", apiBase, pageID)
	return postSubscribe(u, pageToken)
}

// subscribeLeadgen assina os formulários de anúncio. Opcional: sem ele o canal
// de mensagens funciona igual, só os leads de formulário não entram.
func subscribeLeadgen(apiBase, pageID, pageToken string) error {
	u := fmt.Sprintf("%s/%s/subscribed_apps?subscribed_fields=leadgen", apiBase, pageID)
	return postSubscribe(u, pageToken)
}

func postSubscribe(u, pageToken string) error {
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
		return fmt.Errorf("%s", metaErrorMessage(data))
	}
	return nil
}
