package models

// LoginRequest inicia o login: pede o envio de um código OTP para o identificador.
type LoginRequest struct {
	Identifier string `json:"identifier" binding:"required"` // e-mail (ou telefone)
}

// VerifyRequest confirma o login com o código recebido.
type VerifyRequest struct {
	Identifier string `json:"identifier" binding:"required"`
	Code       string `json:"code" binding:"required,len=6"`
}

// RefreshRequest troca um refresh token por um novo par de tokens.
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// AuthResponse é o retorno do login/refresh: tokens + o usuário autenticado.
type AuthResponse struct {
	AccessToken  string       `json:"access_token"`
	RefreshToken string       `json:"refresh_token"`
	User         UserResponse `json:"user"`
}
