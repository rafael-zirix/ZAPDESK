package services

import (
	"sync"
	"testing"
	"time"
)

func TestRateLimiterBloqueiaAlemDoMaximo(t *testing.T) {
	l := NewRateLimiter(3, time.Minute)
	for i := 0; i < 3; i++ {
		if !l.Allow("a") {
			t.Fatalf("tentativa %d deveria passar", i+1)
		}
	}
	if l.Allow("a") {
		t.Fatal("a 4ª tentativa deveria ser bloqueada")
	}
	// Chave diferente não pode herdar o bloqueio da outra.
	if !l.Allow("b") {
		t.Fatal("outra chave deveria passar")
	}
}

func TestRateLimiterLiberaAposAJanela(t *testing.T) {
	l := NewRateLimiter(1, 20*time.Millisecond)
	if !l.Allow("a") {
		t.Fatal("primeira deveria passar")
	}
	if l.Allow("a") {
		t.Fatal("segunda, dentro da janela, deveria bloquear")
	}
	time.Sleep(30 * time.Millisecond)
	if !l.Allow("a") {
		t.Fatal("depois da janela deveria liberar")
	}
}

func TestRateLimiterReset(t *testing.T) {
	l := NewRateLimiter(1, time.Minute)
	l.Allow("a")
	if l.Allow("a") {
		t.Fatal("deveria estar bloqueado")
	}
	l.Reset("a")
	if !l.Allow("a") {
		t.Fatal("após o reset deveria liberar")
	}
}

// O limite não pode escorrer sob concorrência: é exatamente assim que um
// atacante tenta furá-lo — muitas requisições ao mesmo tempo, não em fila.
func TestRateLimiterConcorrente(t *testing.T) {
	l := NewRateLimiter(10, time.Minute)
	var wg sync.WaitGroup
	var mu sync.Mutex
	passaram := 0
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if l.Allow("a") {
				mu.Lock()
				passaram++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()
	if passaram != 10 {
		t.Fatalf("deveriam passar exatamente 10, passaram %d", passaram)
	}
}
