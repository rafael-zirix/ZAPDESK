package models

// Fase 4: métricas de atendimento — agregadas dos eventos e mensagens que as
// fases 1–3 já gravam (nenhuma tabela nova).

// SupportMetrics é o dashboard de atendimento de um período.
type SupportMetrics struct {
	From string `json:"from"`
	To   string `json:"to"`

	TicketsCreated  int `json:"tickets_created"`
	TicketsResolved int `json:"tickets_resolved"` // eventos → resolved/closed no período
	OpenNow         int `json:"open_now"`         // abertos neste momento (independe do período)
	QueueNow        int `json:"queue_now"`        // abertos SEM atendente agora
	Transfers       int `json:"transfers"`
	AIResolved      int `json:"ai_resolved"` // resolvidos sem nenhuma resposta humana

	AvgFirstResponseSec *float64 `json:"avg_first_response_sec,omitempty"` // TME (1ª resposta humana)
	AvgResolutionSec    *float64 `json:"avg_resolution_sec,omitempty"`    // TMA (criação → resolução)

	PerAttendant []AttendantMetrics `json:"per_attendant"`
	PerSector    []SectorMetrics    `json:"per_sector"`
	ByDay        []DayCount         `json:"by_day"`
	ByHour       []HourCount        `json:"by_hour"`
}

// AttendantMetrics é a linha por atendente.
type AttendantMetrics struct {
	UserID       string `json:"user_id"`
	Name         string `json:"name"`
	Resolved     int    `json:"resolved"`      // resoluções feitas por ele no período
	MessagesSent int    `json:"messages_sent"` // respostas enviadas (sem notas)
	OpenAssigned int    `json:"open_assigned"` // em atendimento agora
}

// SectorMetrics é a linha por setor.
type SectorMetrics struct {
	SectorID string `json:"sector_id"`
	Name     string `json:"name"`
	Created  int    `json:"created"`  // conversas do setor criadas no período
	Resolved int    `json:"resolved"` // resolvidas no período
	OpenNow  int    `json:"open_now"`
}

// DayCount é um ponto do gráfico por dia (dia local UTC-3).
type DayCount struct {
	Day   string `json:"day"` // YYYY-MM-DD
	Count int    `json:"count"`
}

// HourCount é um ponto da distribuição por hora do dia (0–23, local UTC-3).
type HourCount struct {
	Hour  int `json:"hour"`
	Count int `json:"count"`
}
