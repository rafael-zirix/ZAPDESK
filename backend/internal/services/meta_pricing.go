package services

// Tabela de preços da META por categoria — visão do DONO da plataforma.
//
// Importante: quem paga a Meta é o CLIENTE (o número fica na conta de WhatsApp
// dele, e a Meta cobra lá). Esta tabela existe para o dono da plataforma
// acompanhar o custo de mercado e precificar os próprios serviços — ela NUNCA
// aparece para o cliente.
//
// Os valores são atualizados sozinhos a partir do que a Meta reporta em
// conversation_analytics (custo real observado ÷ conversas, por categoria) e
// podem ser ajustados à mão pelo super-admin.

import (
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/url"
	"sort"
	"strings"
	"time"
)

// MetaCategoryPrice é a linha da tabela: preço por categoria.
type MetaCategoryPrice struct {
	Category string  `json:"category"` // MARKETING | UTILITY | AUTHENTICATION | SERVICE
	Price    float64 `json:"price"`    // custo unitário observado (moeda da conta)
	Count    int     `json:"count"`    // conversas/mensagens observadas no período
	Cost     float64 `json:"cost"`     // custo total observado no período
}

// MetaPricingTable é a tabela completa com a data da última atualização.
type MetaPricingTable struct {
	Currency  string              `json:"currency"`
	UpdatedAt *time.Time          `json:"updated_at,omitempty"`
	Source    string              `json:"source"` // "meta" (automática) ou "manual"
	Rows      []MetaCategoryPrice `json:"rows"`
	Note      string              `json:"note,omitempty"` // aviso quando não deu para atualizar
}

const metaPricingKey = "meta_pricing_table"

// MetaPricing lê a tabela guardada (vazia se nunca foi atualizada).
func (s *SupportService) MetaPricing() (MetaPricingTable, error) {
	raw, err := s.repo.GetSetting(metaPricingKey)
	if err != nil || raw == "" {
		return MetaPricingTable{Currency: "BRL", Rows: []MetaCategoryPrice{}}, err
	}
	var t MetaPricingTable
	if err := json.Unmarshal([]byte(raw), &t); err != nil {
		return MetaPricingTable{Currency: "BRL", Rows: []MetaCategoryPrice{}}, nil
	}
	if t.Rows == nil {
		t.Rows = []MetaCategoryPrice{}
	}
	return t, nil
}

// SaveMetaPricing grava a tabela (edição manual do super-admin).
func (s *SupportService) SaveMetaPricing(t MetaPricingTable) error {
	now := time.Now().UTC()
	t.UpdatedAt = &now
	if t.Source == "" {
		t.Source = "manual"
	}
	if t.Currency == "" {
		t.Currency = "BRL"
	}
	b, _ := json.Marshal(t)
	return s.repo.SetSetting(metaPricingKey, string(b))
}

// RefreshMetaPricing consulta a Meta (todos os números conectados) e recalcula o
// custo por categoria dos últimos 30 dias. Devolve a tabela atualizada.
func (s *SupportService) RefreshMetaPricing() (MetaPricingTable, error) {
	end := time.Now().UTC()
	start := end.AddDate(0, 0, -30)

	agg := map[string]*MetaCategoryPrice{}
	currency := ""
	wabas := 0

	if s.wa == nil || s.cipher == nil {
		return MetaPricingTable{Currency: "BRL", Rows: []MetaCategoryPrice{},
			Note: "Nenhum número conectado."}, nil
	}
	accounts, err := s.wa.ConnectedAll()
	if err != nil {
		return MetaPricingTable{}, err
	}
	for _, w := range accounts {
		token, err := s.cipher.Decrypt(w.AccessTokenEnc)
		if err != nil {
			continue
		}
		client := NewMetaClient(s.apiBase, token, w.PhoneNumberID)
		rows, cur, err := client.PricingByCategory(w.WabaID, start.Unix(), end.Unix())
		if err != nil {
			slog.Warn("tabela da Meta: falha ao consultar", "waba", w.WabaID, "erro", err)
			continue
		}
		wabas++
		if cur != "" {
			currency = cur
		}
		for _, r := range rows {
			e, ok := agg[r.Category]
			if !ok {
				e = &MetaCategoryPrice{Category: r.Category}
				agg[r.Category] = e
			}
			e.Count += r.Count
			e.Cost += r.Cost
		}
	}

	t := MetaPricingTable{Currency: currency, Source: "meta", Rows: []MetaCategoryPrice{}}
	if t.Currency == "" {
		t.Currency = "BRL"
	}
	for _, e := range agg {
		if e.Count > 0 {
			e.Price = e.Cost / float64(e.Count)
		}
		t.Rows = append(t.Rows, *e)
	}
	// Ordem estável e previsível na tela.
	order := map[string]int{"MARKETING": 0, "UTILITY": 1, "AUTHENTICATION": 2, "SERVICE": 3}
	sort.Slice(t.Rows, func(i, j int) bool {
		oi, oj := order[t.Rows[i].Category], order[t.Rows[j].Category]
		if oi != oj {
			return oi < oj
		}
		return t.Rows[i].Category < t.Rows[j].Category
	})
	if wabas == 0 {
		t.Note = "Nenhum número conectado respondeu à Meta — a tabela mantém os últimos valores conhecidos."
		// Preserva o que já existia em vez de zerar a tela.
		if old, _ := s.MetaPricing(); len(old.Rows) > 0 {
			old.Note = t.Note
			return old, nil
		}
		return t, nil
	}
	if len(t.Rows) == 0 {
		t.Note = "A Meta não reportou custo no período (números novos ou sem envio pago)."
	}
	if err := s.SaveMetaPricing(t); err != nil {
		return t, err
	}
	return s.MetaPricing()
}

// StartMetaPricingWorker atualiza a tabela da Meta diariamente (e uma vez no
// start, após 1 min) — "sempre atualizada" sem depender de clique.
func (s *SupportService) StartMetaPricingWorker() {
	go func() {
		time.Sleep(time.Minute)
		for {
			if _, err := s.RefreshMetaPricing(); err != nil {
				slog.Warn("tabela da Meta: atualização automática falhou", "erro", err)
			}
			time.Sleep(24 * time.Hour)
		}
	}()
	slog.Info("atualização diária da tabela de preços da Meta ativa")
}

// PricingByCategory devolve o custo da Meta por CATEGORIA de conversa no
// período. Usa a dimensão CONVERSATION_CATEGORY do conversation_analytics.
func (c *MetaClient) PricingByCategory(wabaID string, start, end int64) ([]MetaCategoryPrice, string, error) {
	u := fmt.Sprintf(
		"%s/%s?fields=conversation_analytics.start(%d).end(%d).granularity(MONTHLY).dimensions(%%5B%%22CONVERSATION_CATEGORY%%22%%5D)&access_token=%s",
		c.apiBase, wabaID, start, end, url.QueryEscape(c.token))
	resp, err := c.http.Get(u)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return nil, "", fmt.Errorf("%s", metaErrorMessage(data))
	}
	var raw struct {
		ConversationAnalytics struct {
			Data []struct {
				DataPoints []struct {
					Category     string  `json:"conversation_category"`
					Conversation int     `json:"conversation"`
					Cost         float64 `json:"cost"`
				} `json:"data_points"`
			} `json:"data"`
		} `json:"conversation_analytics"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, "", err
	}
	byCat := map[string]*MetaCategoryPrice{}
	for _, d := range raw.ConversationAnalytics.Data {
		for _, p := range d.DataPoints {
			cat := strings.ToUpper(p.Category)
			if cat == "" {
				cat = "OUTRAS"
			}
			e, ok := byCat[cat]
			if !ok {
				e = &MetaCategoryPrice{Category: cat}
				byCat[cat] = e
			}
			e.Count += p.Conversation
			e.Cost += p.Cost
		}
	}
	out := make([]MetaCategoryPrice, 0, len(byCat))
	for _, e := range byCat {
		if e.Count > 0 {
			e.Price = e.Cost / float64(e.Count)
		}
		out = append(out, *e)
	}
	return out, "", nil
}
