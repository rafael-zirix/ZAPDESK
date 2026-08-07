package services

import (
	"encoding/json"

	"zapdesk/internal/repository"
)

// modulePricesKey guarda a TABELA de preços dos módulos em platform_settings
// (mesmo lugar dos preços da Meta e da IA). Preço por conta continua em
// account_modules.price_cents e ganha da tabela.
const modulePricesKey = "module_prices"

// WithSettings liga o repositório que guarda a tabela de preços da plataforma.
func (s *ModuleService) WithSettings(repo *repository.SupportRepository) *ModuleService {
	s.settings = repo
	return s
}

// TablePrices devolve o preço de tabela de cada módulo (chave → centavos).
func (s *ModuleService) TablePrices() map[string]int {
	out := map[string]int{}
	if s.settings == nil {
		return out
	}
	raw, err := s.settings.GetSetting(modulePricesKey)
	if err != nil || raw == "" {
		return out
	}
	_ = json.Unmarshal([]byte(raw), &out)
	return out
}

// SetTablePrices grava a tabela (o que aparece na vitrine de quem ainda não
// negociou preço próprio).
func (s *ModuleService) SetTablePrices(precos map[string]int) error {
	limpo := map[string]int{}
	for k, v := range precos {
		if knownModule(k) && v > 0 {
			limpo[k] = v
		}
	}
	raw, err := json.Marshal(limpo)
	if err != nil {
		return err
	}
	return s.settings.SetSetting(modulePricesKey, string(raw))
}
