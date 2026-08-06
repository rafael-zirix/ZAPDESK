package services

// Fase 3: campanhas de WhatsApp — criação, controle e o worker de envio com
// ritmo controlado (protege a qualidade do número na Meta).

import (
	"errors"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"
	"time"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var (
	ErrCampaignNotFound   = errors.New("campanha não encontrada")
	ErrCampaignBadState   = errors.New("ação não permitida neste status")
	ErrCampaignNoAudience = errors.New("audiência vazia")
)

// CreateCampaign cria a campanha (audiência resolvida na hora, sem opt-outs).
func (s *SupportService) CreateCampaign(accountID, userID string, req models.CreateCampaignRequest) (*models.Campaign, error) {
	if req.TemplateLang == "" {
		req.TemplateLang = "pt_BR"
	}
	if req.RatePerMin < 1 || req.RatePerMin > 60 {
		req.RatePerMin = 12
	}
	if req.Audience == "groups" && len(req.GroupIDs) == 0 {
		return nil, ErrCampaignNoAudience
	}
	sched := time.Now().UTC()
	if req.ScheduledAt != nil {
		sched = req.ScheduledAt.UTC()
	}
	// Categoria do modelo: define quanto a Meta cobra por mensagem entregue.
	req.TemplateCategory = s.templateCategory(accountID, req.TemplateName)
	c, err := s.repo.CreateCampaign(accountID, userID, req, sched)
	if err != nil {
		return nil, err
	}
	if c.Funnel.Total == 0 {
		// Sem destinatário nenhum (audiência vazia ou todos com opt-out): não
		// deixa a campanha órfã.
		_, _ = s.repo.SetCampaignStatus(accountID, c.ID, models.CampaignCanceled)
		return nil, ErrCampaignNoAudience
	}
	return c, nil
}

func (s *SupportService) ListCampaigns(accountID string) ([]models.Campaign, error) {
	return s.repo.ListCampaigns(accountID)
}

func (s *SupportService) GetCampaign(accountID, id string) (*models.Campaign, error) {
	c, err := s.repo.GetCampaign(accountID, id)
	if err != nil {
		return nil, err
	}
	if c == nil {
		return nil, ErrCampaignNotFound
	}
	return c, nil
}

func (s *SupportService) ListCampaignRecipients(accountID, id string, limit int) ([]models.CampaignRecipient, error) {
	if _, err := s.GetCampaign(accountID, id); err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	return s.repo.ListCampaignRecipients(accountID, id, limit)
}

// DeleteCampaign apaga a campanha (e seus destinatários). Uma campanha em
// execução é cancelada antes, para o worker não continuar enviando.
func (s *SupportService) DeleteCampaign(accountID, id string) error {
	c, err := s.GetCampaign(accountID, id)
	if err != nil {
		return err
	}
	if c.Status == models.CampaignRunning || c.Status == models.CampaignScheduled {
		_, _ = s.repo.SetCampaignStatus(accountID, id, models.CampaignCanceled)
	}
	ok, err := s.repo.DeleteCampaign(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrCampaignNotFound
	}
	return nil
}

// SetCampaignAction aplica pausar/retomar/cancelar com as transições válidas.
func (s *SupportService) SetCampaignAction(accountID, id, action string) (*models.Campaign, error) {
	c, err := s.GetCampaign(accountID, id)
	if err != nil {
		return nil, err
	}
	var target string
	switch action {
	case "pause":
		if c.Status != models.CampaignRunning && c.Status != models.CampaignScheduled {
			return nil, ErrCampaignBadState
		}
		target = models.CampaignPaused
	case "resume":
		if c.Status != models.CampaignPaused {
			return nil, ErrCampaignBadState
		}
		// Agendamento ainda no futuro → volta a "agendada" (o worker só pega
		// running; sem isto, retomar dispararia antes da hora).
		if c.ScheduledAt.After(time.Now().UTC()) {
			target = models.CampaignScheduled
		} else {
			target = models.CampaignRunning
		}
	case "cancel":
		if c.Status == models.CampaignDone || c.Status == models.CampaignCanceled {
			return nil, ErrCampaignBadState
		}
		target = models.CampaignCanceled
	default:
		return nil, ErrCampaignBadState
	}
	if _, err := s.repo.SetCampaignStatus(accountID, id, target); err != nil {
		return nil, err
	}
	return s.GetCampaign(accountID, id)
}

// StartCampaignWorker liga o worker de envio: a cada tick, cada campanha em
// execução envia um lote respeitando o seu ritmo (rate_per_min), medido pelo
// que foi de fato enviado no último minuto.
func (s *SupportService) StartCampaignWorker() {
	go func() {
		const tick = 15 * time.Second
		for {
			time.Sleep(tick)
			s.campaignTick()
		}
	}()
	slog.Info("worker de campanhas ativo")
}

func (s *SupportService) campaignTick() {
	jobs, err := s.repo.DueCampaigns()
	if err != nil {
		slog.Error("campanhas: falha ao buscar pendentes", "erro", err)
		return
	}
	for _, j := range jobs {
		sent, err := s.repo.SentInLastMinute(j.ID)
		if err != nil {
			continue
		}
		allowed := j.RatePerMin - sent
		if allowed <= 0 {
			continue
		}
		// Espalha o ritmo pelos ticks (4 ticks/min) para não sair em rajada.
		batch := (j.RatePerMin + 3) / 4
		if batch > allowed {
			batch = allowed
		}
		recs, err := s.repo.NextPendingRecipients(j.ID, batch)
		if err != nil || len(recs) == 0 {
			_ = s.repo.FinishCampaignIfDone(j.ID)
			continue
		}
		client, _, err := s.clientFor(j.AccountID)
		if err != nil || client == nil {
			// Conta sem número conectado: falha o lote com um erro claro (não
			// fica pendente para sempre).
			msg := "nenhum número de WhatsApp conectado"
			for _, rec := range recs {
				_ = s.repo.MarkRecipientSent(rec.ID, nil, &msg)
			}
			_ = s.repo.FinishCampaignIfDone(j.ID)
			continue
		}
		for _, rec := range recs {
			// {nome} nos parâmetros vira o nome do contato (personalização).
			params := personalizeParams(j.Params, rec)
			wamid, sendErr := client.SendTemplateParams(rec.Phone, j.TemplateName, j.TemplateLang, params, j.ImageURL)
			if sendErr != nil {
				msg := sendErr.Error()
				_ = s.repo.MarkRecipientSent(rec.ID, nil, &msg)
				continue
			}
			var ext *string
			if wamid != "" {
				ext = &wamid
			}
			_ = s.repo.MarkRecipientSent(rec.ID, ext, nil)
			// Registra na CONVERSA do contato: o cliente recebeu esta mensagem,
			// então ela precisa aparecer no histórico do atendimento (e é onde a
			// resposta dele vai chegar).
			s.logCampaignMessage(j, rec, ext)
		}
		_ = s.repo.FinishCampaignIfDone(j.ID)
	}
}

// logCampaignMessage grava o disparo na conversa do contato, para o atendente
// ver no histórico o que foi enviado (e a resposta cair na mesma thread).
func (s *SupportService) logCampaignMessage(j repository.CampaignJob, rec models.CampaignRecipient, wamid *string) {
	ticketID, err := s.repo.TicketForCampaign(j.AccountID, rec.ContactID)
	if err != nil || ticketID == "" {
		return
	}
	// Texto: o corpo do modelo com as variáveis já substituídas (o que o
	// cliente realmente recebeu).
	content := j.TemplateName
	if j.BodyText != "" {
		content = j.BodyText
		for i, p := range personalizeParams(j.Params, rec) {
			content = strings.ReplaceAll(content, placeholder(i+1), p)
		}
	}
	tplName := j.TemplateName
	msg := &models.SupportMessage{
		AccountID:    j.AccountID,
		TicketID:     ticketID,
		Direction:    models.DirectionOut,
		Type:         "template",
		Content:      &content,
		Status:       "sent",
		ExternalID:   wamid,
		TemplateName: &tplName,
	}
	if j.TemplateCategory != "" {
		cat := j.TemplateCategory
		msg.TemplateCategory = &cat
	}
	if j.ImageURL != "" {
		url := j.ImageURL
		msg.MediaURL = &url
		msg.Type = "image"
	}
	_, _ = s.repo.InsertMessage(msg)
}

// WithPublicURL informa a URL pública da API (base dos links de mídia de campanha).
func (s *SupportService) WithPublicURL(url string) *SupportService {
	s.publicURL = strings.TrimRight(url, "/")
	return s
}

// SaveCampaignMedia grava a foto da campanha na pasta de mídia e devolve a URL
// PÚBLICA (a Meta baixa a imagem por este link ao entregar o template).
func (s *SupportService) SaveCampaignMedia(data []byte, filename string) (string, error) {
	ext := strings.ToLower(filepath.Ext(filename))
	if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
		return "", errors.New("envie uma imagem JPG ou PNG")
	}
	name, err := s.saveMedia(data, ext)
	if err != nil {
		return "", err
	}
	if s.publicURL == "" {
		return "/media/" + name, nil // dev sem PUBLIC_URL: link relativo (Meta não baixa)
	}
	return s.publicURL + "/media/" + name, nil
}

// placeholder devolve o marcador de variável do modelo ({{1}}, {{2}}…).
func placeholder(n int) string { return fmt.Sprintf("{{%d}}", n) }

// personalizeParams troca o curinga {nome} pelo nome do contato (ou "cliente").
func personalizeParams(params []string, rec models.CampaignRecipient) []string {
	if len(params) == 0 {
		return nil
	}
	name := "cliente"
	if rec.ContactName != nil && strings.TrimSpace(*rec.ContactName) != "" {
		name = strings.TrimSpace(*rec.ContactName)
	}
	out := make([]string, len(params))
	for i, p := range params {
		p = strings.ReplaceAll(p, "{nome}", name)
		p = strings.ReplaceAll(p, "{NOME}", name)
		out[i] = p
	}
	return out
}

// isOptOutMessage detecta o pedido de descadastro ("SAIR" e variações).
func isOptOutMessage(text string) bool {
	switch strings.ToUpper(strings.TrimSpace(text)) {
	case "SAIR", "PARAR", "CANCELAR INSCRIÇÃO", "DESCADASTRAR", "STOP":
		return true
	}
	return false
}
