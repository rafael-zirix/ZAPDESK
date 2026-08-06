package repository

// Fase 4: métricas de atendimento. Tudo agregado do que já existe:
// support_tickets, support_ticket_messages e support_ticket_events.
// Dia/hora "locais" seguem UTC-3 fixo (Brasil sem horário de verão).

import (
	"time"

	"zapdesk/internal/models"
)

// SupportMetrics calcula o dashboard do período [from, to).
func (r *SupportRepository) SupportMetrics(accountID string, from, to time.Time) (*models.SupportMetrics, error) {
	m := &models.SupportMetrics{
		From:         from.Format("2006-01-02"),
		To:           to.AddDate(0, 0, -1).Format("2006-01-02"),
		PerAttendant: []models.AttendantMetrics{},
		PerSector:    []models.SectorMetrics{},
		ByDay:        []models.DayCount{},
		ByHour:       []models.HourCount{},
	}

	// Totais: criados no período, abertos/fila agora.
	err := r.db.QueryRow(`
		SELECT
		  (SELECT COUNT(*) FROM support_tickets WHERE account_id=$1 AND created_at >= $2 AND created_at < $3),
		  (SELECT COUNT(*) FROM support_tickets WHERE account_id=$1 AND status IN ('open','pending')),
		  (SELECT COUNT(*) FROM support_tickets WHERE account_id=$1 AND status='open' AND assigned_user_id IS NULL),
		  (SELECT COUNT(*) FROM support_ticket_events WHERE account_id=$1 AND kind='transferred' AND created_at >= $2 AND created_at < $3)`,
		accountID, from, to).
		Scan(&m.TicketsCreated, &m.OpenNow, &m.QueueNow, &m.Transfers)
	if err != nil {
		return nil, err
	}

	// Resolvidos no período + TMA + resolvidos sem humano (IA/bot).
	// "Resolução" = 1º evento resolved/closed do ticket dentro do período.
	err = r.db.QueryRow(`
		WITH res AS (
			SELECT e.ticket_id, MIN(e.created_at) AS resolved_at
			FROM support_ticket_events e
			WHERE e.account_id=$1 AND e.kind='status_changed'
			  AND e.to_status IN ('resolved','closed')
			  AND e.created_at >= $2 AND e.created_at < $3
			GROUP BY e.ticket_id
		)
		SELECT COUNT(*),
		       AVG(EXTRACT(EPOCH FROM (res.resolved_at - t.created_at))),
		       COUNT(*) FILTER (WHERE NOT EXISTS (
		           SELECT 1 FROM support_ticket_messages hm
		           WHERE hm.ticket_id = t.id AND hm.direction='out'
		             AND hm.sender_id IS NOT NULL AND COALESCE(hm.internal,false)=false))
		FROM res JOIN support_tickets t ON t.id = res.ticket_id`,
		accountID, from, to).
		Scan(&m.TicketsResolved, &m.AvgResolutionSec, &m.AIResolved)
	if err != nil {
		return nil, err
	}

	// TME: tempo até a 1ª resposta HUMANA (sem notas), dos tickets criados no período.
	err = r.db.QueryRow(`
		WITH fr AS (
			SELECT t.id, t.created_at,
			       (SELECT MIN(mm.created_at) FROM support_ticket_messages mm
			        WHERE mm.ticket_id = t.id AND mm.direction='out'
			          AND mm.sender_id IS NOT NULL AND COALESCE(mm.internal,false)=false) AS first_reply
			FROM support_tickets t
			WHERE t.account_id=$1 AND t.created_at >= $2 AND t.created_at < $3
		)
		SELECT AVG(EXTRACT(EPOCH FROM (first_reply - created_at)))
		FROM fr WHERE first_reply IS NOT NULL`,
		accountID, from, to).Scan(&m.AvgFirstResponseSec)
	if err != nil {
		return nil, err
	}

	// Por atendente: resoluções + respostas enviadas no período, e carga atual.
	rows, err := r.db.Query(`
		SELECT u.id, u.full_name,
		  COALESCE((SELECT COUNT(DISTINCT e.ticket_id) FROM support_ticket_events e
		            WHERE e.account_id=$1 AND e.actor_user_id=u.id AND e.kind='status_changed'
		              AND e.to_status IN ('resolved','closed') AND e.created_at >= $2 AND e.created_at < $3), 0),
		  COALESCE((SELECT COUNT(*) FROM support_ticket_messages sm
		            WHERE sm.account_id=$1 AND sm.sender_id=u.id AND sm.direction='out'
		              AND COALESCE(sm.internal,false)=false AND sm.created_at >= $2 AND sm.created_at < $3), 0),
		  COALESCE((SELECT COUNT(*) FROM support_tickets t
		            WHERE t.account_id=$1 AND t.assigned_user_id=u.id AND t.status IN ('open','pending')), 0)
		FROM users u
		WHERE u.account_id=$1 AND u.deleted_at IS NULL
		ORDER BY u.full_name`, accountID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var a models.AttendantMetrics
		if err := rows.Scan(&a.UserID, &a.Name, &a.Resolved, &a.MessagesSent, &a.OpenAssigned); err != nil {
			return nil, err
		}
		// Só entra na tabela quem teve alguma atividade (ou carga atual).
		if a.Resolved > 0 || a.MessagesSent > 0 || a.OpenAssigned > 0 {
			m.PerAttendant = append(m.PerAttendant, a)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Por setor.
	rows, err = r.db.Query(`
		SELECT s.id, s.name,
		  COALESCE((SELECT COUNT(*) FROM support_tickets t
		            WHERE t.sector_id=s.id AND t.created_at >= $2 AND t.created_at < $3), 0),
		  COALESCE((SELECT COUNT(DISTINCT e.ticket_id) FROM support_ticket_events e
		            JOIN support_tickets t2 ON t2.id = e.ticket_id
		            WHERE t2.sector_id=s.id AND e.kind='status_changed'
		              AND e.to_status IN ('resolved','closed') AND e.created_at >= $2 AND e.created_at < $3), 0),
		  COALESCE((SELECT COUNT(*) FROM support_tickets t3
		            WHERE t3.sector_id=s.id AND t3.status IN ('open','pending')), 0)
		FROM support_sectors s
		WHERE s.account_id=$1
		ORDER BY s.name`, accountID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var sm models.SectorMetrics
		if err := rows.Scan(&sm.SectorID, &sm.Name, &sm.Created, &sm.Resolved, &sm.OpenNow); err != nil {
			return nil, err
		}
		m.PerSector = append(m.PerSector, sm)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Conversas criadas por DIA local (UTC-3).
	rows, err = r.db.Query(`
		SELECT to_char((created_at - interval '3 hours')::date, 'YYYY-MM-DD'), COUNT(*)
		FROM support_tickets
		WHERE account_id=$1 AND created_at >= $2 AND created_at < $3
		GROUP BY 1 ORDER BY 1`, accountID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var d models.DayCount
		if err := rows.Scan(&d.Day, &d.Count); err != nil {
			return nil, err
		}
		m.ByDay = append(m.ByDay, d)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	// Distribuição por HORA do dia local (picos → dimensionar a equipe).
	rows, err = r.db.Query(`
		SELECT EXTRACT(HOUR FROM (created_at - interval '3 hours'))::int, COUNT(*)
		FROM support_tickets
		WHERE account_id=$1 AND created_at >= $2 AND created_at < $3
		GROUP BY 1 ORDER BY 1`, accountID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var h models.HourCount
		if err := rows.Scan(&h.Hour, &h.Count); err != nil {
			return nil, err
		}
		m.ByHour = append(m.ByHour, h)
	}
	return m, rows.Err()
}
