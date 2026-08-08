package handlers

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

// PackageHandler é o CRUD de pacotes comerciais (super-admin) e a lista de
// valores dos pacotes de crédito avulso.
type PackageHandler struct {
	repo     *repository.PackageRepository
	settings *repository.SupportRepository // guarda os valores de crédito (platform_settings)
}

func NewPackageHandler(repo *repository.PackageRepository, settings *repository.SupportRepository) *PackageHandler {
	return &PackageHandler{repo: repo, settings: settings}
}

// creditPacksKey guarda os VALORES em reais dos pacotes de crédito. São só valores;
// a quantidade de token que cada um rende é calculada por IA na hora da compra —
// por isso a lista é uma só, e não uma por IA.
const creditPacksKey = "credit_pack_values"

var defaultCreditPacks = []int{3000, 6000, 15000, 30000} // centavos: R$ 30, 60, 150, 300

func (h *PackageHandler) List(c *gin.Context) {
	items, err := h.repo.List(false)
	if err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao listar os pacotes", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "OK", items)
}

// bindPackage lê o corpo e recusa o que não faz sentido antes de gravar.
func bindPackage(c *gin.Context) (*models.Package, bool) {
	var p models.Package
	if err := c.ShouldBindJSON(&p); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dados do pacote inválidos", err.Error())
		return nil, false
	}
	p.Name = strings.TrimSpace(p.Name)
	if p.Name == "" {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Dê um nome ao pacote", nil)
		return nil, false
	}
	if p.IncLines < 1 {
		p.IncLines = 1
	}
	if p.IncAgents < 1 {
		p.IncAgents = 1
	}
	// Franquia só faz sentido com IA no pacote.
	if !p.IncIA {
		p.FranchiseCents = 0
	}
	// Nada de valor negativo escapando para a vitrine.
	for _, v := range []*int{&p.PriceMonthCents, &p.LineAddonCents, &p.FranchiseCents} {
		if *v < 0 {
			*v = 0
		}
	}
	return &p, true
}

func (h *PackageHandler) Create(c *gin.Context) {
	p, ok := bindPackage(c)
	if !ok {
		return
	}
	if err := h.repo.Create(p); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao criar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusCreated, "Pacote criado", p)
}

func (h *PackageHandler) Update(c *gin.Context) {
	p, ok := bindPackage(c)
	if !ok {
		return
	}
	p.ID = c.Param("id")
	if err := h.repo.Update(p); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Não foi possível salvar o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pacote salvo", p)
}

func (h *PackageHandler) Delete(c *gin.Context) {
	if err := h.repo.Delete(c.Param("id")); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao excluir o pacote", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Pacote excluído", nil)
}

// CreditPacks devolve os valores (em centavos) dos pacotes de crédito avulso.
func (h *PackageHandler) CreditPacks(c *gin.Context) {
	RespondSuccess(c, http.StatusOK, "OK", gin.H{"values_cents": h.creditPackValues()})
}

func (h *PackageHandler) SetCreditPacks(c *gin.Context) {
	var req struct {
		ValuesCents []int `json:"values_cents"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		RespondError(c, http.StatusBadRequest, ErrValidation, "Valores inválidos", err.Error())
		return
	}
	vals := make([]int, 0, len(req.ValuesCents))
	for _, v := range req.ValuesCents {
		if v > 0 {
			vals = append(vals, v)
		}
	}
	raw, _ := json.Marshal(vals)
	if err := h.settings.SetSetting(creditPacksKey, string(raw)); err != nil {
		RespondError(c, http.StatusInternalServerError, ErrInternal, "Erro ao salvar os valores", nil)
		return
	}
	RespondSuccess(c, http.StatusOK, "Valores salvos", gin.H{"values_cents": vals})
}

func (h *PackageHandler) creditPackValues() []int {
	raw, err := h.settings.GetSetting(creditPacksKey)
	if err != nil || strings.TrimSpace(raw) == "" {
		return defaultCreditPacks
	}
	var vals []int
	if json.Unmarshal([]byte(raw), &vals) != nil || len(vals) == 0 {
		return defaultCreditPacks
	}
	return vals
}
