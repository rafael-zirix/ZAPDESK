package models

// OnboardingStatus resume o progresso do primeiro acesso do cliente (para o
// checklist guiado) e se ele já concluiu/dispensou o guia.
type OnboardingStatus struct {
	Done            bool `json:"done"`
	HasWhatsApp     bool `json:"has_whatsapp"`
	AIEnabled       bool `json:"ai_enabled"`
	HasInstructions bool `json:"has_instructions"`
	HasKnowledge    bool `json:"has_knowledge"`
	HasActions      bool `json:"has_actions"`
	HasCredits      bool `json:"has_credits"`
	TeamSize        int  `json:"team_size"`
}
