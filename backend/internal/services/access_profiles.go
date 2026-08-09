package services

import (
	"errors"
	"strings"

	"github.com/lib/pq"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var (
	ErrProfileNotFound  = errors.New("perfil não encontrado")
	ErrProfileNameTaken = errors.New("já existe um perfil com este nome")
	ErrProfileBadPerm   = errors.New("permissão desconhecida")
)

// PermCatalog é a árvore de funções do sistema — espelha o menu do painel.
// O que NÃO está aqui não é delegável: plano/cobrança/tokens e o próprio
// editor de perfis seguem exclusivos do admin (regra de negócio, em pedra).
func PermCatalog() []models.PermGroup {
	return []models.PermGroup{
		{Label: "Atendimento", Items: []models.PermDef{
			{Key: "atendimento", Label: "Conversas (WhatsApp e Instagram)", HasWrite: true},
			{Key: "metricas", Label: "Métricas de atendimento", HasWrite: false},
		}},
		{Label: "Cadastros", Items: []models.PermDef{
			{Key: "contatos", Label: "Contatos", HasWrite: true},
			{Key: "contatos_ficha", Label: "Ficha completa do contato (CPF/CNPJ, endereço)", HasWrite: true},
			{Key: "usuarios", Label: "Usuários da empresa", HasWrite: true},
			{Key: "setores", Label: "Setores", HasWrite: true},
			{Key: "etiquetas", Label: "Etiquetas", HasWrite: true},
		}},
		{Label: "CRM", Items: []models.PermDef{
			{Key: "crm", Label: "Quadro e leads", HasWrite: true},
			{Key: "crm_etapas", Label: "Etapas e motivos do funil", HasWrite: true},
			{Key: "crm_relatorios", Label: "Funil, métricas e perdidos", HasWrite: false},
		}},
		{Label: "Marketing", Items: []models.PermDef{
			{Key: "campanhas", Label: "Campanhas", HasWrite: true},
			{Key: "modelos", Label: "Modelos de mensagem", HasWrite: true},
		}},
		{Label: "Canais", Items: []models.PermDef{
			{Key: "telefones", Label: "Números de WhatsApp", HasWrite: true},
			{Key: "instagram", Label: "Conexão do Instagram", HasWrite: true},
		}},
		{Label: "Atendente IA", Items: []models.PermDef{
			{Key: "ia", Label: "Configuração e base de conhecimento", HasWrite: true},
		}},
	}
}

// validPermKeys indexa o catálogo para validação.
func validPermKeys() map[string]models.PermDef {
	out := map[string]models.PermDef{}
	for _, g := range PermCatalog() {
		for _, it := range g.Items {
			out[it.Key] = it
		}
	}
	return out
}

// AccessProfileService aplica as regras dos perfis: chaves válidas, gravar
// implica ver, e a resolução das permissões por usuário.
type AccessProfileService struct {
	repo *repository.AccessProfileRepository
}

func NewAccessProfileService(repo *repository.AccessProfileRepository) *AccessProfileService {
	return &AccessProfileService{repo: repo}
}

// UserPerms implementa o PermChecker do middleware.
func (s *AccessProfileService) UserPerms(userID string) (*string, map[string]models.Perm, error) {
	return s.repo.UserPerms(userID)
}

func (s *AccessProfileService) List(accountID string) ([]models.AccessProfile, error) {
	return s.repo.List(accountID)
}

// normalize valida as chaves e aplica as regras: gravar ⇒ ver; função
// somente-leitura nunca ganha gravar.
func normalizePerms(perms map[string]models.Perm) (map[string]models.Perm, error) {
	valid := validPermKeys()
	out := map[string]models.Perm{}
	for key, p := range perms {
		def, ok := valid[key]
		if !ok {
			return nil, ErrProfileBadPerm
		}
		if !def.HasWrite {
			p.Write = false
		}
		if p.Write {
			p.View = true
		}
		if p.View || p.Write {
			out[key] = p
		}
	}
	return out, nil
}

func (s *AccessProfileService) Create(accountID string, req models.AccessProfileRequest) (string, error) {
	perms, err := normalizePerms(req.Perms)
	if err != nil {
		return "", err
	}
	id, err := s.repo.Create(accountID, strings.TrimSpace(req.Name), perms)
	if isProfileUnique(err) {
		return "", ErrProfileNameTaken
	}
	return id, err
}

func (s *AccessProfileService) Update(accountID, id string, req models.AccessProfileRequest) error {
	perms, err := normalizePerms(req.Perms)
	if err != nil {
		return err
	}
	ok, err := s.repo.Update(accountID, id, strings.TrimSpace(req.Name), perms)
	if isProfileUnique(err) {
		return ErrProfileNameTaken
	}
	if err == nil && !ok {
		return ErrProfileNotFound
	}
	return err
}

func (s *AccessProfileService) Delete(accountID, id string) error {
	ok, err := s.repo.Delete(accountID, id)
	if err == nil && !ok {
		return ErrProfileNotFound
	}
	return err
}

func isProfileUnique(err error) bool {
	var pqErr *pq.Error
	return err != nil && errors.As(err, &pqErr) && pqErr.Code == "23505"
}
