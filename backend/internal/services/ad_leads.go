package services

import (
	"log/slog"
	"strings"

	"zapdesk/internal/models"
)

// AdReferral é o bloco `referral` que a Meta manda junto da primeira mensagem
// de quem clicou num anúncio Click-to-WhatsApp.
type AdReferral struct {
	SourceID   string // id do anúncio
	SourceType string // "ad" | "post"
	SourceURL  string
	Headline   string
	CtwaClid   string // id do clique (liga a conversa ao anúncio nos relatórios da Meta)
}

// Cor da etiqueta automática dos leads de anúncio (laranja da marca da campanha).
const adTagColor = "#F79009"

// ApplyAdReferral carimba a origem do anúncio na conversa e faz o que o lead
// precisa para não se perder: etiqueta ("Anúncio: …"), no contato e na conversa,
// e manda para o setor comercial escolhido pela empresa.
//
// Só age na PRIMEIRA vez (o carimbo é único por conversa): quem volta pelo mesmo
// anúncio não é re-roteado por cima de um atendimento em andamento.
func (s *SupportService) ApplyAdReferral(accountID, ticketID string, ref AdReferral) {
	if ref.SourceID == "" && ref.Headline == "" {
		return
	}
	first, err := s.repo.SetTicketAd(accountID, ticketID, ref.SourceID, ref.Headline)
	if err != nil {
		slog.Error("lead de anúncio: falha ao carimbar a origem", "erro", err, "ticket", ticketID)
		return
	}
	if !first {
		return
	}
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil || ticket == nil {
		return
	}
	// Etiqueta pelo anúncio: é o que deixa o filtro e a campanha enxergarem a
	// origem depois, sem tela nova.
	if tag, err := s.repo.FindOrCreateTag(accountID, adTagName(ref), adTagColor); err == nil {
		_ = s.repo.AddTicketTag(ticketID, tag.ID)
		_ = s.repo.AddContactTag(ticket.ContactID, tag.ID)
	}
	// Roteia para o setor de anúncios (Comercial), sem tirar quem já assumiu.
	sectorID, err := s.repo.AdDefaultSectorID(accountID)
	if err == nil && sectorID != "" && ticket.SectorID == nil && ticket.AssignedUserID == nil {
		if err := s.repo.UpdateTicketRouting(accountID, ticketID, nil, false, &sectorID, true); err != nil {
			slog.Error("lead de anúncio: falha ao rotear", "erro", err, "ticket", ticketID)
		}
	}
	nota := "📣 Lead de anúncio: " + adTagName(ref)
	if ref.SourceURL != "" {
		nota += "\n" + ref.SourceURL
	}
	s.systemNote(accountID, ticketID, nota)
}

// adTagName monta o nome curto da etiqueta do anúncio.
func adTagName(ref AdReferral) string {
	h := strings.TrimSpace(ref.Headline)
	if h == "" {
		return "Anúncio " + ref.SourceID
	}
	if len([]rune(h)) > 40 {
		h = string([]rune(h)[:40]) + "…"
	}
	return "Anúncio: " + h
}

// systemNote grava uma nota interna SEM autor (foi o sistema, não uma pessoa).
// A nota interna comum exige um usuário; esta não.
func (s *SupportService) systemNote(accountID, ticketID, text string) {
	body := strings.TrimSpace(text)
	if body == "" {
		return
	}
	_, err := s.repo.InsertMessage(&models.SupportMessage{
		AccountID: accountID,
		TicketID:  ticketID,
		Direction: models.DirectionOut,
		Type:      "text",
		Content:   &body,
		Status:    "note",
		Internal:  true,
	})
	if err != nil {
		slog.Error("nota do sistema: falha ao gravar", "erro", err, "ticket", ticketID)
	}
}

// Nome da ferramenta embutida com que a IA entrega a conversa a uma pessoa.
const toolHandoff = "encaminhar_atendente"

// handoffToHuman é o que acontece quando a IA decide passar a bola: a conversa
// vai para a fila do setor (o de anúncios quando o lead veio de um), a IA se
// cala nesta conversa e o resumo dela vira nota interna para o atendente ler
// antes de dar o primeiro "oi". Devolve o texto que a IA lê de volta.
func (s *SupportService) handoffToHuman(accountID, ticketID, resumo string) string {
	if ticketID == "" {
		return "Não foi possível encaminhar agora."
	}
	ticket, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil || ticket == nil {
		return "Não foi possível encaminhar agora."
	}
	// Sem setor definido, o lead de anúncio vai para o setor comercial escolhido.
	if ticket.SectorID == nil {
		if sectorID, err := s.repo.AdDefaultSectorID(accountID); err == nil && sectorID != "" {
			_ = s.repo.UpdateTicketRouting(accountID, ticketID, nil, false, &sectorID, true)
		}
	}
	nota := "🤖 A IA encaminhou para atendimento humano."
	if r := strings.TrimSpace(resumo); r != "" {
		nota += "\n" + r
	}
	if headline, err := s.repo.TicketAdHeadline(accountID, ticketID); err == nil && headline != "" {
		nota += "\n📣 Origem: " + headline
	}
	s.systemNote(accountID, ticketID, nota)
	// A IA para de responder aqui: quem fala com o cliente agora é a pessoa.
	if s.aiRepo != nil {
		_ = s.aiRepo.SetTicketAIPaused(accountID, ticketID, true)
	}
	slog.Info("IA encaminhou a conversa", "ticket", ticketID)
	return "Conversa encaminhada para um atendente humano. Avise o cliente em uma frase curta e não faça mais perguntas."
}

// SetAdSector define qual setor recebe os leads de anúncio (vazio = nenhum).
func (s *SupportService) SetAdSector(accountID, sectorID string) error {
	return s.repo.SetAdDefaultSector(accountID, sectorID)
}
