package services

import (
	"errors"
	"net"
	"net/http"
	"syscall"
	"time"
)

// ErrBlockedTarget sai quando uma Ação da IA tenta falar com um endereço interno.
var ErrBlockedTarget = errors.New("destino não permitido (endereço interno)")

// safeHTTPClient é o cliente usado pelas Ações da IA, onde a URL é escolhida
// pelo CLIENTE. Sem cuidado, isso vira SSRF: alguém cadastra uma ação apontando
// para 169.254.169.254 (metadados da nuvem), para o Postgres na rede interna ou
// para o próprio serviço, e usa o nosso servidor como ponte.
//
// A checagem fica no DIAL, sobre o IP realmente resolvido — não sobre o texto da
// URL. Isso cobre três buracos de uma vez: domínio público que aponta para IP
// privado, DNS que muda entre a validação e a conexão (rebinding), e redirecionamento
// para um alvo interno (cada salto abre uma conexão nova e passa pelo mesmo filtro).
func safeHTTPClient() *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second, KeepAlive: 30 * time.Second, Control: blockInternalDial}
	return &http.Client{
		Timeout:   20 * time.Second,
		Transport: &http.Transport{DialContext: dialer.DialContext, TLSHandshakeTimeout: 10 * time.Second},
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 3 {
				return errors.New("muitos redirecionamentos")
			}
			return guardURL(req.URL.String())
		},
	}
}

// blockInternalDial recusa a conexão quando o IP de destino não é público.
func blockInternalDial(_, address string, _ syscall.RawConn) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return ErrBlockedTarget
	}
	ip := net.ParseIP(host)
	if ip == nil || !isPublicIP(ip) {
		return ErrBlockedTarget
	}
	return nil
}

// isPublicIP diz se o endereço é roteável na internet. Fora daqui ficam
// loopback, redes privadas, link-local (inclui os metadados da nuvem em
// 169.254.169.254), multicast e a faixa de operadora 100.64/10.
func isPublicIP(ip net.IP) bool {
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsMulticast() || ip.IsInterfaceLocalMulticast() {
		return false
	}
	if v4 := ip.To4(); v4 != nil && v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127 {
		return false // CGNAT (100.64.0.0/10)
	}
	return true
}
