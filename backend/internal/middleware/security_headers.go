package middleware

import "github.com/gin-gonic/gin"

// SecurityHeaders aplica as defesas que o navegador sabe executar sozinho.
//
// Ficam aqui e não no Caddy de propósito: o Caddy daquela VM atende vários
// sistemas, e regra de segurança escrita em arquivo compartilhado se perde na
// primeira vez que alguém mexe em outro site. Aqui elas viajam junto com o app.
func SecurityHeaders(isDev bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Sem isto, o painel pode ser embutido num iframe e sobreposto por uma
		// tela falsa — o clique vai para o botão real, escondido embaixo.
		c.Header("X-Frame-Options", "DENY")
		// Impede o navegador de "adivinhar" o tipo de um arquivo enviado por um
		// cliente e executá-lo como script.
		c.Header("X-Content-Type-Options", "nosniff")
		// A URL do painel pode conter ids de conversa; não vaza para terceiros.
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "geolocation=(), camera=(), microphone=(self), payment=()")
		// Só faz sentido sob HTTPS, e em dev (http://localhost) quebraria o acesso.
		if !isDev {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		// CSP sob medida para o Flutter Web: ele usa wasm e workers, e o popup da
		// Meta precisa ser permitido como destino de formulário/frame.
		// 'unsafe-inline' em style-src é exigência do próprio Flutter.
		//
		// gstatic.com está liberado de propósito: o build passou a embarcar o
		// CanvasKit (--no-web-resources-cdn), mas quem tiver o bootstrap ANTIGO em
		// cache ainda vai buscá-lo lá — e uma CSP que trava esse navegador entrega
		// tela branca a um cliente que não fez nada de errado.
		c.Header("Content-Security-Policy",
			"default-src 'self'; "+
				"script-src 'self' 'wasm-unsafe-eval' https://connect.facebook.net https://www.gstatic.com; "+
				"style-src 'self' 'unsafe-inline'; "+
				"img-src 'self' data: blob: https:; "+
				"media-src 'self' data: blob:; "+
				// O Flutter cria workers a partir de Blob (renderer skwasm) e
				// registra o service worker. Sem esta linha eles herdariam
				// default-src 'self', blob: seria barrado e o app não pintaria
				// nada em parte dos navegadores.
				"worker-src 'self' blob:; "+
				"font-src 'self' data:; "+
				"connect-src 'self' https://graph.facebook.com https://www.facebook.com https://www.gstatic.com; "+
				"frame-src https://www.facebook.com https://web.facebook.com; "+
				"form-action 'self' https://www.facebook.com; "+
				"frame-ancestors 'none'; "+
				"base-uri 'self'; "+
				"object-src 'none'")
		c.Next()
	}
}
