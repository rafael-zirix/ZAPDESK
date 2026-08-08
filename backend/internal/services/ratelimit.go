package services

import (
	"sync"
	"time"
)

// RateLimiter é uma janela deslizante em memória, por chave.
//
// Em memória e não no banco porque o custo tem de ser menor que o do ataque: um
// limitador que grava a cada tentativa vira ele mesmo o gargalo. A contrapartida
// é que o limite é POR PROCESSO — com várias réplicas, cada uma tem a sua conta.
// Isso é aceitável aqui porque o limite duro do login mora no banco (as
// tentativas por código, em ConsumeOTP); este limitador é a primeira barreira,
// não a última.
type RateLimiter struct {
	mu       sync.Mutex
	eventos  map[string][]time.Time
	max      int
	janela   time.Duration
	ultimaLx time.Time // última limpeza
}

func NewRateLimiter(max int, janela time.Duration) *RateLimiter {
	return &RateLimiter{eventos: map[string][]time.Time{}, max: max, janela: janela}
}

// Allow registra uma tentativa e diz se ela cabe no limite.
func (l *RateLimiter) Allow(chave string) bool {
	agora := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	l.limpar(agora)

	corte := agora.Add(-l.janela)
	lista := l.eventos[chave][:0]
	for _, t := range l.eventos[chave] {
		if t.After(corte) {
			lista = append(lista, t)
		}
	}
	if len(lista) >= l.max {
		l.eventos[chave] = lista
		return false
	}
	l.eventos[chave] = append(lista, agora)
	return true
}

// Reset zera a contagem de uma chave (usado após um login bem-sucedido: quem
// provou quem é não deve carregar o peso das tentativas anteriores).
func (l *RateLimiter) Reset(chave string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.eventos, chave)
}

// limpar descarta chaves vencidas. Sem isto o mapa cresce para sempre, e um
// atacante variando o identificador viraria um vazamento de memória — ou seja,
// o próprio limitador seria o alvo.
func (l *RateLimiter) limpar(agora time.Time) {
	if agora.Sub(l.ultimaLx) < l.janela {
		return
	}
	l.ultimaLx = agora
	corte := agora.Add(-l.janela)
	for k, v := range l.eventos {
		if len(v) == 0 || v[len(v)-1].Before(corte) {
			delete(l.eventos, k)
		}
	}
}
