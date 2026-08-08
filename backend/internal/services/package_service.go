package services

import (
	"errors"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// PackageService liga um pacote comercial ao mundo real: quando o super-admin
// atribui um pacote a uma empresa, ele APLICA o que o pacote inclui — módulos
// ligados/desligados e limites de linhas/atendentes. Sem isto o pacote seria só
// um texto bonito; é aqui que ele passa a valer.
type PackageService struct {
	pkgs    *repository.PackageRepository
	modules *ModuleService
}

func NewPackageService(pkgs *repository.PackageRepository, modules *ModuleService) *PackageService {
	return &PackageService{pkgs: pkgs, modules: modules}
}

var ErrPackageNotFound = errors.New("pacote não encontrado")

// Assign atribui o pacote à empresa e aplica o que ele inclui.
//
// Aplicar = casar o estado da conta com o pacote: os módulos do pacote ficam
// ligados, os de fora ficam desligados, e os limites passam a ser os do pacote.
// É idempotente — reatribuir o mesmo pacote não muda nada.
func (s *PackageService) Assign(accountID, packageID string) (*models.Package, error) {
	p, err := s.pkgs.Get(packageID)
	if err != nil {
		return nil, err
	}
	if p == nil {
		return nil, ErrPackageNotFound
	}
	// Módulos: liga os que o pacote inclui, desliga os demais. O atendimento é o
	// núcleo e nunca é mexido aqui.
	inc := map[string]bool{
		ModuleIA:        p.IncIA,
		ModuleInstagram: p.IncInstagram,
		ModuleCampanhas: p.IncCampanhas,
		ModuleMetricas:  p.IncMetricas,
	}
	for key, on := range inc {
		if err := s.modules.Set(accountID, key, on, nil, nil); err != nil {
			return nil, err
		}
	}
	// Limites: atendentes e linhas vêm do pacote. A retenção de histórico é
	// preservada (o pacote não a define) — leio a atual para não encolher.
	hist := 90
	if cur, err := s.modules.Limits(accountID); err == nil && cur.HistoryDays > 0 {
		hist = cur.HistoryDays
	}
	if err := s.modules.SetLimits(accountID, p.IncAgents, p.IncLines, hist); err != nil {
		return nil, err
	}
	if err := s.pkgs.AssignToAccount(accountID, packageID); err != nil {
		return nil, err
	}
	return p, nil
}

// Current devolve o pacote da empresa (nil = nenhum atribuído ainda).
func (s *PackageService) Current(accountID string) (*models.Package, error) {
	return s.pkgs.AccountPackage(accountID)
}
