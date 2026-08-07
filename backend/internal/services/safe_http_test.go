package services

import (
	"net"
	"testing"
)

// A URL das Ações da IA é escolhida pelo cliente: o filtro de destino interno é
// o que impede usar o nosso servidor como ponte para a rede/metadados da nuvem.
func TestIsPublicIP(t *testing.T) {
	bloqueados := []string{
		"127.0.0.1",          // loopback
		"10.1.2.3",           // rede privada
		"192.168.0.10",       // rede privada
		"172.16.5.4",         // rede privada
		"169.254.169.254",    // metadados da nuvem
		"100.100.1.1",        // CGNAT
		"0.0.0.0",            // não especificado
		"::1",                // loopback IPv6
		"fd00::1",            // ULA IPv6
		"224.0.0.1",          // multicast
		"::ffff:192.168.1.1", // privado mapeado em IPv6
	}
	for _, s := range bloqueados {
		if isPublicIP(net.ParseIP(s)) {
			t.Errorf("%s deveria ser bloqueado", s)
		}
	}
	for _, s := range []string{"8.8.8.8", "1.1.1.1", "2001:4860:4860::8888"} {
		if !isPublicIP(net.ParseIP(s)) {
			t.Errorf("%s deveria ser permitido", s)
		}
	}
}

func TestGuardURL(t *testing.T) {
	ruins := []string{
		"file:///etc/passwd",
		"ftp://exemplo.com",
		"http://localhost:8080/x",
		"http://algo.local/x",
		"http://127.0.0.1/x",
		"http://169.254.169.254/latest/meta-data/",
	}
	for _, u := range ruins {
		if err := guardURL(u); err == nil {
			t.Errorf("%s deveria ser recusada", u)
		}
	}
	if err := guardURL("https://api.exemplo.com/consulta?doc={doc}"); err != nil {
		t.Errorf("URL pública recusada: %v", err)
	}
}
