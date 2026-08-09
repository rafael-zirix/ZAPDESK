package models

import "time"

// Status do negócio no funil.
const (
	CrmDealOpen = "open"
	CrmDealWon  = "won"
	CrmDealLost = "lost"
)

// CrmStage é uma coluna do Kanban — editável por conta. is_system protege as
// âncoras do funil (entrada e ganho): renomear pode, excluir não.
type CrmStage struct {
	ID        string    `json:"id"`
	AccountID string    `json:"-"`
	Name      string    `json:"name"`
	Color     string    `json:"color"`
	Ordinal   int       `json:"ordinal"`
	IsWon     bool      `json:"is_won"`
	IsSystem  bool      `json:"is_system"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CrmLossReason é um motivo de perda (editável por conta).
type CrmLossReason struct {
	ID        string `json:"id"`
	AccountID string `json:"-"`
	Name      string `json:"name"`
	Ordinal   int    `json:"ordinal"`
}

// CrmDeal é o card do Kanban. Não copia dados de pessoa: contact_id aponta o
// cadastro ÚNICO (support_contacts); os campos Contact*/Owner* vêm por join,
// só para exibição.
type CrmDeal struct {
	ID             string     `json:"id"`
	AccountID      string     `json:"-"`
	ContactID      string     `json:"contact_id"`
	StageID        string     `json:"stage_id"`
	OwnerUserID    *string    `json:"owner_user_id"`
	TicketID       *string    `json:"ticket_id"`
	Title          *string    `json:"title"`
	ValueCents     int64      `json:"value_cents"`
	Status         string     `json:"status"`
	Source         *string    `json:"source"`
	SourceDetail   *string    `json:"source_detail"`
	Notes          *string    `json:"notes"`
	NextFollowUpAt *time.Time `json:"next_follow_up_at"`
	WonAt          *time.Time `json:"won_at"`
	LostAt         *time.Time `json:"lost_at"`
	LostReasonID   *string    `json:"lost_reason_id"`
	LostNotes      *string    `json:"lost_notes"`
	SortOrder      int        `json:"sort_order"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`

	ContactName    *string `json:"contact_name"`
	ContactPhone   *string `json:"contact_phone"`
	ContactCompany *string `json:"contact_company"`
	OwnerName      *string `json:"owner_name"`
	LostReasonName *string `json:"lost_reason_name,omitempty"`
}

// CrmDealFilter recorta a listagem de negócios.
type CrmDealFilter struct {
	OwnerID         *string    // admin filtrando por vendedor
	VisibleToUserID *string    // atendente: só os SEUS + os sem dono
	Status          *string    // open | won | lost
	ExcludeLost     bool       // quadro: abertos E ganhos (perdido sai do board)
	StageID         *string
	From, To        *time.Time // open→created_at, lost→lost_at, won→won_at
}

// CrmStageRequest cria/edita uma etapa.
type CrmStageRequest struct {
	Name    string  `json:"name" binding:"required,min=1"`
	Color   *string `json:"color"`
	Ordinal *int    `json:"ordinal"`
	IsWon   *bool   `json:"is_won"`
}

// UpdateCrmStageRequest edita uma etapa (parcial: campo ausente mantém).
type UpdateCrmStageRequest struct {
	Name    *string `json:"name"`
	Color   *string `json:"color"`
	Ordinal *int    `json:"ordinal"`
	IsWon   *bool   `json:"is_won"`
}

// CrmLossReasonRequest cria/edita um motivo de perda.
type CrmLossReasonRequest struct {
	Name    string `json:"name" binding:"required,min=1"`
	Ordinal *int   `json:"ordinal"`
}

// CreateCrmDealRequest abre um negócio: com um contato existente (contact_id)
// OU criando/reusando um pelo telefone (cadastro único — telefone repetido
// reaproveita o contato).
type CreateCrmDealRequest struct {
	ContactID      string  `json:"contact_id"`
	ContactName    string  `json:"contact_name"`
	ContactPhone   string  `json:"contact_phone"`
	StageID        string  `json:"stage_id"` // vazio = primeira etapa
	Title          *string `json:"title"`
	ValueCents     int64   `json:"value_cents"`
	Source         *string `json:"source"`
	Notes          *string `json:"notes"`
	OwnerUserID    *string `json:"owner_user_id"`
	NextFollowUpAt *string `json:"next_follow_up_at"` // YYYY-MM-DD (UTC-3)
}

// UpdateCrmDealRequest edita campos do negócio (parcial).
type UpdateCrmDealRequest struct {
	Title          *string `json:"title"`
	ValueCents     *int64  `json:"value_cents"`
	Source         *string `json:"source"`
	Notes          *string `json:"notes"`
	OwnerUserID    *string `json:"owner_user_id"`
	NextFollowUpAt *string `json:"next_follow_up_at"` // YYYY-MM-DD; "" limpa
}

// MoveCrmDealRequest muda o card de coluna (drag & drop).
type MoveCrmDealRequest struct {
	StageID   string `json:"stage_id" binding:"required"`
	SortOrder *int   `json:"sort_order"`
}

// LoseCrmDealRequest marca o negócio como perdido.
type LoseCrmDealRequest struct {
	LostReasonID *string `json:"lost_reason_id"`
	LostNotes    *string `json:"lost_notes"`
}

// CrmFunnelRow é uma etapa no funil de conversão (contagem + valor somado,
// sem os perdidos).
type CrmFunnelRow struct {
	StageID   string `json:"stage_id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	Ordinal   int    `json:"ordinal"`
	IsWon     bool   `json:"is_won"`
	DealCount int    `json:"deal_count"`
	Value     int64  `json:"total_value_cents"`
}

// CrmReportSummary são os números de cima do relatório. Cada status usa a SUA
// data: aberto→criação, ganho→won_at, perdido→lost_at.
type CrmReportSummary struct {
	OpenCount    int     `json:"open_count"`
	OpenValue    int64   `json:"open_value_cents"`
	WonCount     int     `json:"won_count"`
	WonValue     int64   `json:"won_value_cents"`
	LostCount    int     `json:"lost_count"`
	LostValue    int64   `json:"lost_value_cents"`
	AvgDaysToWin float64 `json:"avg_days_to_win"` // 0 = sem ganhos no recorte
}

// CrmLossRow agrega os perdidos por motivo.
type CrmLossRow struct {
	ReasonID string `json:"reason_id"` // "" = sem motivo
	Reason   string `json:"reason"`
	Count    int    `json:"count"`
	Value    int64  `json:"value_cents"`
}

// CrmReport reúne tudo que as abas Funil/Métricas/Perdidos consomem.
type CrmReport struct {
	Summary   CrmReportSummary `json:"summary"`
	Funnel    []CrmFunnelRow   `json:"funnel"`
	Losses    []CrmLossRow     `json:"losses"`
	LostDeals []CrmDeal        `json:"lost_deals"`
}

// CrmSeller é um usuário da conta no papel de vendedor (filtro/atribuição).
type CrmSeller struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Role string `json:"role"`
}

// ContactFicha é a ficha rica do cadastro único (empresa, documento, endereço)
// — os campos que o CRM acrescentou ao support_contacts.
type ContactFicha struct {
	ID          string  `json:"id"`
	Name        *string `json:"name"`
	Phone       *string `json:"phone"`
	Email       *string `json:"email"`
	PersonType  *string `json:"person_type"` // pf | pj
	Document    *string `json:"document"`    // CPF/CNPJ, só dígitos
	CompanyName *string `json:"company_name"`
	TradeName   *string `json:"trade_name"`
	ZipCode     *string `json:"zip_code"`
	Street      *string `json:"street"`
	Number      *string `json:"number"`
	Complement  *string `json:"complement"`
	District    *string `json:"district"`
	City        *string `json:"city"`
	State       *string `json:"state"`
}

// ContactFichaRequest edita a ficha (parcial; string vazia limpa o campo).
type ContactFichaRequest struct {
	Name        *string `json:"name"`
	Email       *string `json:"email"`
	PersonType  *string `json:"person_type" binding:"omitempty,oneof=pf pj"`
	Document    *string `json:"document"`
	CompanyName *string `json:"company_name"`
	TradeName   *string `json:"trade_name"`
	ZipCode     *string `json:"zip_code"`
	Street      *string `json:"street"`
	Number      *string `json:"number"`
	Complement  *string `json:"complement"`
	District    *string `json:"district"`
	City        *string `json:"city"`
	State       *string `json:"state"`
}
