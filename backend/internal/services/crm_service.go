package services

import (
	"errors"
	"strings"
	"time"

	"github.com/lib/pq"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// Erros de domínio do CRM.
var (
	ErrCrmStageNotFound   = errors.New("etapa não encontrada")
	ErrCrmStageSystem     = errors.New("etapa do sistema não pode ser excluída")
	ErrCrmStageInUse      = errors.New("etapa tem negócios; mova-os antes de excluir")
	ErrCrmStageNameTaken  = errors.New("já existe uma etapa com este nome")
	ErrCrmDealNotFound    = errors.New("negócio não encontrado")
	ErrCrmForbidden       = errors.New("este negócio pertence a outro vendedor")
	ErrCrmContactRequired = errors.New("informe um contato (existente ou nome+telefone)")
	ErrCrmContactNotFound = errors.New("contato não encontrado")
	ErrCrmReasonNotFound  = errors.New("motivo não encontrado")
	ErrCrmReasonNameTaken = errors.New("já existe um motivo com este nome")
	ErrCrmOwnerInvalid    = errors.New("vendedor inválido para esta conta")
)

// O card do CRM exibe datas em UTC-3 fixo (convenção do painel).
const crmUTCOffset = 3 * time.Hour

// CrmService implementa o funil de vendas ligado às conversas. Regra de
// visibilidade espelha a dos contatos: atendente vê os SEUS negócios + os sem
// dono; admin vê tudo e filtra por vendedor.
type CrmService struct {
	repo    *repository.CrmRepository
	support *repository.SupportRepository // cadastro único (find-or-create por telefone)
	// Módulos contratados (ligado no wiring). Nil = não checa.
	hasModule func(accountID, key string) (bool, error)
}

func NewCrmService(repo *repository.CrmRepository, support *repository.SupportRepository) *CrmService {
	return &CrmService{repo: repo, support: support}
}

// WithModuleCheck liga a checagem de módulo (a automação só roda p/ quem contratou).
func (s *CrmService) WithModuleCheck(fn func(accountID, key string) (bool, error)) *CrmService {
	s.hasModule = fn
	return s
}

// AutoCreateLeadDeal abre o card do lead na etapa de ENTRADA do funil — é o
// "lead do Instagram já cai nos leads". Chamado pelo hook do atendimento quando
// um lead de anúncio chega (Lead Ads / Click-to-WhatsApp). Regras: só para
// conta com o módulo 'crm'; idempotente por contato (quem já tem negócio
// ABERTO não ganha outro); nasce SEM dono (a fila é de todos; o dono chega
// quando alguém assume). Best-effort: erro aqui não pode travar o webhook.
func (s *CrmService) AutoCreateLeadDeal(accountID, contactID, ticketID, source, detail string) error {
	if s.hasModule != nil {
		ok, err := s.hasModule(accountID, ModuleCRM)
		if err != nil {
			return err
		}
		if !ok {
			return nil // conta sem CRM: nada a fazer, sem erro
		}
	}
	if err := s.EnsureDefaults(accountID); err != nil {
		return err
	}
	if d, err := s.repo.FindOpenDealByContact(accountID, contactID); err != nil {
		return err
	} else if d != nil {
		return nil // lead voltou: o card aberto já é o lugar dele
	}
	first, err := s.repo.FirstStage(accountID)
	if err != nil {
		return err
	}
	if first == nil {
		return ErrCrmStageNotFound
	}
	deal := &models.CrmDeal{
		AccountID: accountID, ContactID: contactID, StageID: first.ID,
		Source: &source, SourceDetail: &detail,
	}
	if ticketID != "" { // vazio tem que virar NULL, não ''::uuid
		deal.TicketID = &ticketID
	}
	_, err = s.repo.CreateDeal(deal, "") // sem autor: foi o sistema
	return err
}

// EnsureDefaults garante funil e motivos para contas criadas depois da 000047.
func (s *CrmService) EnsureDefaults(accountID string) error {
	n, err := s.repo.CountStages(accountID)
	if err != nil {
		return err
	}
	if n > 0 {
		return nil
	}
	return s.repo.SeedDefaults(accountID)
}

// --- Etapas ---

func (s *CrmService) ListStages(accountID string) ([]models.CrmStage, error) {
	if err := s.EnsureDefaults(accountID); err != nil {
		return nil, err
	}
	return s.repo.ListStages(accountID)
}

func (s *CrmService) CreateStage(accountID string, req models.CrmStageRequest) (*models.CrmStage, error) {
	color := "#0E9384"
	if req.Color != nil && *req.Color != "" {
		color = *req.Color
	}
	ordinal := 0
	if req.Ordinal != nil {
		ordinal = *req.Ordinal
	}
	isWon := req.IsWon != nil && *req.IsWon
	st, err := s.repo.CreateStage(accountID, strings.TrimSpace(req.Name), color, ordinal, isWon)
	if isUnique(err) {
		return nil, ErrCrmStageNameTaken
	}
	return st, err
}

func (s *CrmService) UpdateStage(accountID, id string, req models.UpdateCrmStageRequest) (*models.CrmStage, error) {
	cur, err := s.repo.StageByID(accountID, id)
	if err != nil {
		return nil, err
	}
	if cur == nil {
		return nil, ErrCrmStageNotFound
	}
	// is_won é o caráter da etapa-âncora: nas do sistema não muda.
	isWon := req.IsWon
	if cur.IsSystem {
		isWon = nil
	}
	// Edição parcial: nome ausente/vazio mantém o atual.
	var namePtr *string
	if req.Name != nil {
		if name := strings.TrimSpace(*req.Name); name != "" {
			namePtr = &name
		}
	}
	st, err := s.repo.UpdateStage(accountID, id, namePtr, req.Color, req.Ordinal, isWon)
	if isUnique(err) {
		return nil, ErrCrmStageNameTaken
	}
	if err == nil && st == nil {
		return nil, ErrCrmStageNotFound
	}
	return st, err
}

func (s *CrmService) DeleteStage(accountID, id string) error {
	cur, err := s.repo.StageByID(accountID, id)
	if err != nil {
		return err
	}
	if cur == nil {
		return ErrCrmStageNotFound
	}
	if cur.IsSystem {
		return ErrCrmStageSystem
	}
	if n, err := s.repo.CountDealsByStage(accountID, id); err != nil {
		return err
	} else if n > 0 {
		return ErrCrmStageInUse
	}
	ok, err := s.repo.DeleteStage(accountID, id)
	if isFK(err) {
		// Corrida entre a contagem e o DELETE: um negócio entrou na etapa no
		// meio do caminho — mesma resposta do caso comum, não um 500.
		return ErrCrmStageInUse
	}
	if err == nil && !ok {
		return ErrCrmStageNotFound
	}
	return err
}

// --- Board / listagem ---

// visibility devolve o recorte do papel: atendente enxerga os seus + sem dono.
func visibility(userID string, isAdmin bool) *string {
	if isAdmin {
		return nil
	}
	return &userID
}

// Board devolve etapas + negócios abertos (o Kanban inteiro numa chamada).
func (s *CrmService) Board(accountID, userID string, isAdmin bool, ownerID *string) ([]models.CrmStage, []models.CrmDeal, error) {
	stages, err := s.ListStages(accountID)
	if err != nil {
		return nil, nil, err
	}
	// Abertos E ganhos: a coluna "Fechado" mostra as vitórias; perdido sai do
	// quadro (vive no relatório de perdidos).
	f := models.CrmDealFilter{ExcludeLost: true, VisibleToUserID: visibility(userID, isAdmin)}
	if isAdmin {
		f.OwnerID = ownerID // filtro por vendedor é prerrogativa do admin
	}
	deals, err := s.repo.ListDeals(accountID, f)
	if err != nil {
		return nil, nil, err
	}
	return stages, deals, nil
}

func (s *CrmService) ListDeals(accountID, userID string, isAdmin bool, f models.CrmDealFilter) ([]models.CrmDeal, error) {
	f.VisibleToUserID = visibility(userID, isAdmin)
	if !isAdmin {
		f.OwnerID = nil
	}
	return s.repo.ListDeals(accountID, f)
}

// dealForWrite carrega o negócio e barra atendente mexendo em card alheio.
func (s *CrmService) dealForWrite(accountID, userID string, isAdmin bool, dealID string) (*models.CrmDeal, error) {
	d, err := s.repo.DealByID(accountID, dealID)
	if err != nil {
		return nil, err
	}
	if d == nil {
		return nil, ErrCrmDealNotFound
	}
	if !isAdmin && d.OwnerUserID != nil && *d.OwnerUserID != userID {
		return nil, ErrCrmForbidden
	}
	return d, nil
}

// --- Negócios ---

// CreateDeal abre um negócio. Devolve também se CRIOU de fato: com DedupOpen,
// contato que já tem negócio aberto recebe o card existente (created=false).
func (s *CrmService) CreateDeal(accountID, userID string, isAdmin bool, req models.CreateCrmDealRequest) (deal *models.CrmDeal, created bool, err error) {
	if err := s.EnsureDefaults(accountID); err != nil {
		return nil, false, err
	}
	// Contato: existente, resolvido pela CONVERSA (ticket), ou find-or-create
	// por telefone (cadastro único — telefone repetido reaproveita a ficha em
	// vez de duplicar). Contato criado por aqui nasce DELIBERADAMENTE sem dono
	// (compartilhado, como os do webhook): o dono do NEGÓCIO é quem recorta o
	// funil, não o do contato.
	contactID := strings.TrimSpace(req.ContactID)
	ticketID := strings.TrimSpace(req.TicketID)
	if ticketID != "" {
		t, err := s.support.GetTicket(accountID, ticketID)
		if err != nil {
			return nil, false, err
		}
		if t == nil {
			return nil, false, ErrCrmContactNotFound
		}
		if contactID == "" {
			contactID = t.ContactID
		}
	}
	if contactID == "" {
		name := strings.TrimSpace(req.ContactName)
		phone := strings.TrimSpace(req.ContactPhone)
		if phone == "" {
			return nil, false, ErrCrmContactRequired
		}
		var namePtr *string
		if name != "" {
			namePtr = &name
		}
		ct, err := s.support.FindOrCreateContact(accountID, normalizePhone(phone), namePtr)
		if err != nil {
			return nil, false, err
		}
		contactID = ct.ID
	} else if f, err := s.repo.ContactFicha(accountID, contactID); err != nil {
		return nil, false, err
	} else if f == nil {
		return nil, false, ErrCrmContactNotFound
	}
	// Abrir da conversa é idempotente: lead que já está no funil não duplica.
	if req.DedupOpen {
		if d, err := s.repo.FindOpenDealByContact(accountID, contactID); err != nil {
			return nil, false, err
		} else if d != nil {
			return d, false, nil
		}
	}

	// Etapa: a informada (validada na conta) ou a de entrada.
	stageID := strings.TrimSpace(req.StageID)
	if stageID == "" {
		first, err := s.repo.FirstStage(accountID)
		if err != nil {
			return nil, false, err
		}
		if first == nil {
			return nil, false, ErrCrmStageNotFound
		}
		stageID = first.ID
	} else if st, err := s.repo.StageByID(accountID, stageID); err != nil {
		return nil, false, err
	} else if st == nil {
		return nil, false, ErrCrmStageNotFound
	}

	owner := req.OwnerUserID
	if owner == nil || strings.TrimSpace(*owner) == "" {
		// Atendente abre para si; admin pode deixar sem dono.
		if !isAdmin {
			owner = &userID
		} else {
			owner = nil
		}
	}
	if err := s.validateOwner(accountID, userID, isAdmin, owner); err != nil {
		return nil, false, err
	}
	followUp, _, err := parseCrmDate(req.NextFollowUpAt)
	if err != nil {
		return nil, false, err
	}
	d := &models.CrmDeal{
		AccountID: accountID, ContactID: contactID, StageID: stageID,
		OwnerUserID: owner, Title: req.Title, ValueCents: req.ValueCents,
		Source: req.Source, Notes: req.Notes, NextFollowUpAt: followUp,
	}
	if ticketID != "" { // nascido da conversa: card e atendimento ficam ligados
		d.TicketID = &ticketID
	}
	// O evento de nascimento (from NULL) sai na mesma transação do INSERT.
	deal, err = s.repo.CreateDeal(d, userID)
	return deal, err == nil, err
}

// validateOwner barra dono de fora da conta e atendente atribuindo a outro:
// a FK de owner é global, e a visibilidade (meus + sem dono) depende disso.
func (s *CrmService) validateOwner(accountID, userID string, isAdmin bool, owner *string) error {
	if owner == nil || *owner == "" {
		return nil
	}
	if !isAdmin && *owner != userID {
		return ErrCrmForbidden
	}
	ok, err := s.repo.UserInAccount(accountID, *owner)
	if err != nil {
		return err
	}
	if !ok {
		return ErrCrmOwnerInvalid
	}
	return nil
}

func (s *CrmService) UpdateDeal(accountID, userID string, isAdmin bool, dealID string, req models.UpdateCrmDealRequest) (*models.CrmDeal, error) {
	if _, err := s.dealForWrite(accountID, userID, isAdmin, dealID); err != nil {
		return nil, err
	}
	// Dono segue o contrato do create: "" limpa (vira sem dono), nil mantém.
	clearOwner := false
	if req.OwnerUserID != nil && strings.TrimSpace(*req.OwnerUserID) == "" {
		req.OwnerUserID = nil
		clearOwner = true
	}
	if err := s.validateOwner(accountID, userID, isAdmin, req.OwnerUserID); err != nil {
		return nil, err
	}
	followUp, clear, err := parseCrmDate(req.NextFollowUpAt)
	if err != nil {
		return nil, err
	}
	d, err := s.repo.UpdateDeal(accountID, dealID, req, followUp, clear, clearOwner)
	if err == nil && d == nil {
		return nil, ErrCrmDealNotFound
	}
	return d, err
}

func (s *CrmService) MoveDeal(accountID, userID string, isAdmin bool, dealID string, req models.MoveCrmDealRequest) (*models.CrmDeal, error) {
	if _, err := s.dealForWrite(accountID, userID, isAdmin, dealID); err != nil {
		return nil, err
	}
	st, err := s.repo.StageByID(accountID, req.StageID)
	if err != nil {
		return nil, err
	}
	if st == nil {
		return nil, ErrCrmStageNotFound
	}
	return s.repo.MoveDeal(accountID, dealID, req.StageID, req.SortOrder, st.IsWon, userID)
}

func (s *CrmService) LoseDeal(accountID, userID string, isAdmin bool, dealID string, req models.LoseCrmDealRequest) (*models.CrmDeal, error) {
	if _, err := s.dealForWrite(accountID, userID, isAdmin, dealID); err != nil {
		return nil, err
	}
	// Motivo é opcional; quando vem, tem de ser DA CONTA (a FK é global).
	if req.LostReasonID != nil && strings.TrimSpace(*req.LostReasonID) == "" {
		req.LostReasonID = nil
	}
	if req.LostReasonID != nil {
		ok, err := s.repo.ReasonExists(accountID, *req.LostReasonID)
		if err != nil {
			return nil, err
		}
		if !ok {
			return nil, ErrCrmReasonNotFound
		}
	}
	d, err := s.repo.LoseDeal(accountID, dealID, req.LostReasonID, req.LostNotes)
	if err == nil && d == nil {
		return nil, ErrCrmDealNotFound
	}
	return d, err
}

func (s *CrmService) DeleteDeal(accountID, userID string, isAdmin bool, dealID string) error {
	if _, err := s.dealForWrite(accountID, userID, isAdmin, dealID); err != nil {
		return err
	}
	ok, err := s.repo.DeleteDeal(accountID, dealID)
	if err == nil && !ok {
		return ErrCrmDealNotFound
	}
	return err
}

// Report reúne funil + resumo + perdas + lista de perdidos, já no recorte do
// papel (atendente: os dele + sem dono) e nos filtros de vendedor/período.
func (s *CrmService) Report(accountID, userID string, isAdmin bool, ownerID *string, from, to *time.Time) (*models.CrmReport, error) {
	if err := s.EnsureDefaults(accountID); err != nil {
		return nil, err
	}
	f := models.CrmDealFilter{VisibleToUserID: visibility(userID, isAdmin), From: from, To: to}
	if isAdmin {
		f.OwnerID = ownerID
	}
	summary, err := s.repo.Summary(accountID, f)
	if err != nil {
		return nil, err
	}
	funnel, err := s.repo.Funnel(accountID, f)
	if err != nil {
		return nil, err
	}
	losses, err := s.repo.LossesByReason(accountID, f)
	if err != nil {
		return nil, err
	}
	lost := models.CrmDealLost
	lf := f
	lf.Status = &lost // ListDeals recorta perdido por lost_at
	lostDeals, err := s.repo.ListDeals(accountID, lf)
	if err != nil {
		return nil, err
	}
	return &models.CrmReport{
		Summary: *summary, Funnel: funnel, Losses: losses, LostDeals: lostDeals,
	}, nil
}

// --- Motivos de perda ---

func (s *CrmService) ListLossReasons(accountID string) ([]models.CrmLossReason, error) {
	if err := s.EnsureDefaults(accountID); err != nil {
		return nil, err
	}
	return s.repo.ListLossReasons(accountID)
}

func (s *CrmService) CreateLossReason(accountID string, req models.CrmLossReasonRequest) (*models.CrmLossReason, error) {
	ordinal := 0
	if req.Ordinal != nil {
		ordinal = *req.Ordinal
	}
	m, err := s.repo.CreateLossReason(accountID, strings.TrimSpace(req.Name), ordinal)
	if isUnique(err) {
		return nil, ErrCrmReasonNameTaken
	}
	return m, err
}

func (s *CrmService) UpdateLossReason(accountID, id string, req models.CrmLossReasonRequest) (*models.CrmLossReason, error) {
	m, err := s.repo.UpdateLossReason(accountID, id, strings.TrimSpace(req.Name), req.Ordinal)
	if isUnique(err) {
		return nil, ErrCrmReasonNameTaken
	}
	if err == nil && m == nil {
		return nil, ErrCrmReasonNotFound
	}
	return m, err
}

func (s *CrmService) DeleteLossReason(accountID, id string) error {
	ok, err := s.repo.DeleteLossReason(accountID, id)
	if err == nil && !ok {
		return ErrCrmReasonNotFound
	}
	return err
}

// --- Vendedores / ficha ---

func (s *CrmService) ListSellers(accountID string) ([]models.CrmSeller, error) {
	return s.repo.ListSellers(accountID)
}

// contactForAccess aplica à ficha a régua dos contatos: atendente só chega ao
// contato DELE, sem dono, ou com negócio visível a ele (card sem dono no
// quadro); admin passa. Ficha carrega PII — não vaza entre vendedores.
func (s *CrmService) contactForAccess(accountID, userID string, isAdmin bool, contactID string) error {
	owner, hasVisibleDeal, found, err := s.repo.ContactAccess(accountID, contactID, userID)
	if err != nil {
		return err
	}
	if !found {
		return ErrCrmContactNotFound
	}
	if isAdmin || owner == nil || *owner == userID || hasVisibleDeal {
		return nil
	}
	return ErrCrmForbidden
}

func (s *CrmService) ContactFicha(accountID, userID string, isAdmin bool, contactID string) (*models.ContactFicha, error) {
	if err := s.contactForAccess(accountID, userID, isAdmin, contactID); err != nil {
		return nil, err
	}
	f, err := s.repo.ContactFicha(accountID, contactID)
	if err == nil && f == nil {
		return nil, ErrCrmContactNotFound
	}
	return f, err
}

func (s *CrmService) UpdateContactFicha(accountID, userID string, isAdmin bool, contactID string, req models.ContactFichaRequest) (*models.ContactFicha, error) {
	if err := s.contactForAccess(accountID, userID, isAdmin, contactID); err != nil {
		return nil, err
	}
	// Documento guarda só dígitos — máscara é assunto da tela.
	if req.Document != nil && *req.Document != "" {
		d := nonDigits.ReplaceAllString(*req.Document, "")
		req.Document = &d
	}
	f, err := s.repo.UpdateContactFicha(accountID, contactID, req)
	if err == nil && f == nil {
		return nil, ErrCrmContactNotFound
	}
	return f, err
}

// --- Auxiliares ---

// parseCrmDate converte "YYYY-MM-DD" (dia local UTC-3) na fronteira UTC.
// nil mantém; string vazia sinaliza LIMPAR (clear=true).
func parseCrmDate(v *string) (t *time.Time, clear bool, err error) {
	if v == nil {
		return nil, false, nil
	}
	if strings.TrimSpace(*v) == "" {
		return nil, true, nil
	}
	d, err := time.Parse("2006-01-02", strings.TrimSpace(*v))
	if err != nil {
		return nil, false, err
	}
	utc := d.Add(crmUTCOffset) // 00:00 local = 03:00 UTC
	return &utc, false, nil
}

func isUnique(err error) bool {
	var pqErr *pq.Error
	return err != nil && errors.As(err, &pqErr) && pqErr.Code == "23505"
}

func isFK(err error) bool {
	var pqErr *pq.Error
	return err != nil && errors.As(err, &pqErr) && pqErr.Code == "23503"
}
