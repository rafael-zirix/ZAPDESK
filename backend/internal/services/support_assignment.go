package services

import (
	"errors"
	"log/slog"
	"time"

	"zapdesk/internal/models"
)

// Exclusividade do atendimento.
//
// Regra do produto: assumida a conversa, SÓ o responsável fala com o cliente.
// Quem quiser atender precisa receber a transferência — nem o administrador
// responde por cima (decisão explícita do dono do produto).
//
// A regra vive AQUI, no serviço, e não na tela: esconder o botão no app não
// impede um POST direto na API. Nota interna fica de fora de propósito — ela não
// chega ao cliente e é como um colega ajuda quem está atendendo.

// ErrNotAssignee: a conversa tem outro responsável.
var ErrNotAssignee = errors.New("esta conversa está com outro atendente")

// ErrNotAssigneeOrAdmin: transferir exige ser o responsável ou administrador.
var ErrNotAssigneeOrAdmin = errors.New("só o responsável ou um administrador pode transferir esta conversa")

// ensureAssignee barra o envio ao cliente quando quem escreve não é o dono da
// conversa. Silencioso (nil) quando a conta desligou a exclusividade, quando
// ninguém assumiu ainda, ou quando o próprio dono está falando.
//
// Recebe o ticket já carregado porque todo caminho de envio busca o ticket antes
// de qualquer coisa — repetir a consulta aqui dobraria o custo de cada mensagem.
//
// Passe userID vazio para as ações do sistema (Atendente IA, campanhas, bot):
// elas não pertencem a ninguém e continuam livres.
func (s *SupportService) ensureAssignee(accountID, userID string, t *models.SupportTicket) error {
	if userID == "" || t == nil {
		return nil
	}
	if t.AssignedUserID == nil || *t.AssignedUserID == "" || *t.AssignedUserID == userID {
		return nil
	}
	exclusive, _, err := s.repo.AccountAssignmentPolicy(accountID)
	if err != nil {
		// Falha FECHADO: sem saber a política, recusa. Deixar passar transformaria
		// um blip do banco em "todo mundo responde a conversa de todo mundo" — e
		// ninguém perceberia, porque o erro seria só uma linha de log.
		slog.Error("exclusividade: não foi possível ler a política da conta", "erro", err, "conta", accountID)
		return ErrNotAssignee
	}
	if !exclusive {
		return nil
	}
	return ErrNotAssignee
}

// humanTookOver registra que um humano falou com o cliente nesta conversa e
// pausa o Atendente IA (handoff).
//
// Precisa valer para TODO envio humano — antes só a resposta de TEXTO pausava, e
// quem mandava só um anexo, um modelo ou a localização continuava com o bot
// respondendo por cima dele na mensagem seguinte do cliente.
//
// Best-effort: falhar aqui não pode impedir a mensagem de sair.
func (s *SupportService) humanTookOver(accountID, ticketID, userID string) {
	if userID == "" || s.aiRepo == nil {
		return
	}
	_ = s.aiRepo.SetTicketAIPaused(accountID, ticketID, true)
}

// ensureCanSend é o [ensureAssignee] para quem ainda não tem o ticket em mãos
// (reenvio de mensagem, encaminhamento).
func (s *SupportService) ensureCanSend(accountID, ticketID, userID string) error {
	if userID == "" {
		return nil
	}
	t, err := s.repo.GetTicket(accountID, ticketID)
	if err != nil {
		return err
	}
	if t == nil {
		return ErrTicketNotFound
	}
	return s.ensureAssignee(accountID, userID, t)
}

// StartTicketReleaseWorker devolve à fila as conversas presas com um atendente
// que sumiu. Roda de minuto em minuto; cada conta define o prazo
// (release_after_minutes; 0 desliga).
//
// Só libera com o CLIENTE ESPERANDO — a última mensagem tem de ser dele. Quem
// assumiu, respondeu e ficou aguardando o cliente não perde a conversa por ter
// saído para almoçar.
func (s *SupportService) StartTicketReleaseWorker() {
	go func() {
		// Espera um pouco no boot: no startup o servidor ainda está aplicando
		// migrações e aquecendo conexões.
		time.Sleep(time.Minute)
		for {
			s.releaseStaleTickets()
			time.Sleep(time.Minute)
		}
	}()
}

func (s *SupportService) releaseStaleTickets() {
	defer func() {
		if r := recover(); r != nil {
			slog.Error("liberação automática: pânico", "erro", r)
		}
	}()
	presas, err := s.repo.StaleAssignedTickets()
	if err != nil {
		slog.Error("liberação automática: falha ao buscar conversas", "erro", err)
		return
	}
	for _, t := range presas {
		// Condicional ao dono que o SELECT viu: entre a consulta e o UPDATE, o
		// atendente pode ter voltado e assumido — e ele não pode perder a conversa
		// por causa da janela do worker.
		liberou, err := s.repo.ReleaseTicketIfStillOwned(t.AccountID, t.TicketID, t.AssignedUserID)
		if err != nil {
			slog.Error("liberação automática: falha ao devolver à fila", "erro", err, "ticket", t.TicketID)
			continue
		}
		if !liberou {
			continue // mudou de dono no meio do caminho: nada a fazer
		}
		// Sem registro no histórico, o atendente volta e não entende por que a
		// conversa saiu das mãos dele.
		nota := "Devolvida à fila automaticamente: o cliente ficou aguardando resposta."
		_ = s.repo.InsertTicketEvent(t.AccountID, t.TicketID, &models.SupportTicketEvent{
			Kind:       models.TicketEventTransferred,
			FromUserID: &t.AssignedUserID,
			Note:       &nota,
		})
		slog.Info("conversa devolvida à fila por inatividade",
			"ticket", t.TicketID, "atendente", t.AssignedUserID, "minutos", t.IdleMinutes)
	}
}
