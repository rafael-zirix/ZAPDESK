package models

import "time"

// AccountDetails é a ficha completa da empresa: pessoa física/jurídica,
// documento, contato e endereço. Campos opcionais (podem ser preenchidos
// depois). Reaproveitado no registro, na resposta e nos requests.
type AccountDetails struct {
	PersonType *string `json:"person_type,omitempty" binding:"omitempty,oneof=pf pj"` // pf | pj
	Document   *string `json:"document,omitempty"`                                   // CPF ou CNPJ
	TradeName  *string `json:"trade_name,omitempty"`                                 // nome fantasia (PJ)
	Email      *string `json:"email,omitempty" binding:"omitempty,email"`
	Phone      *string `json:"phone,omitempty"`
	ZipCode    *string `json:"zip_code,omitempty"`
	Street     *string `json:"street,omitempty"`
	Number     *string `json:"number,omitempty"`
	Complement *string `json:"complement,omitempty"`
	District   *string `json:"district,omitempty"` // bairro
	City       *string `json:"city,omitempty"`
	State      *string `json:"state,omitempty"` // UF
}

// Account é uma empresa cliente do SaaS (tenant).
type Account struct {
	ID        string
	Name      string
	Slug      *string
	Status    string
	CreatedAt time.Time
	AccountDetails
}

// AccountResponse é a representação pública de uma empresa (com contagens úteis).
type AccountResponse struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Slug         *string   `json:"slug,omitempty"`
	Status       string    `json:"status"`
	CreatedAt    time.Time `json:"created_at"`
	NumbersCount int       `json:"numbers_count"`
	AccountDetails
}

// WhatsAppAccount é o número de WhatsApp de uma empresa (credenciais Meta).
type WhatsAppAccount struct {
	ID              string
	AccountID       string
	WabaID          string
	PhoneNumberID   string
	DisplayPhone    *string
	VerifiedName    *string
	AccessTokenEnc  string
	AppSecretEnc    *string
	VerifyToken     *string
	Status          string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// WhatsAppAccountResponse NUNCA expõe o token/segredo — só os identificadores.
type WhatsAppAccountResponse struct {
	ID            string    `json:"id"`
	AccountID     string    `json:"account_id"`
	WabaID        string    `json:"waba_id"`
	PhoneNumberID string    `json:"phone_number_id"`
	DisplayPhone  *string   `json:"display_phone,omitempty"`
	VerifiedName  *string   `json:"verified_name,omitempty"`
	Status        string    `json:"status"`
	CreatedAt     time.Time `json:"created_at"`
}

// ToResponse converte o número para a resposta pública (sem segredos).
func (w *WhatsAppAccount) ToResponse() WhatsAppAccountResponse {
	return WhatsAppAccountResponse{
		ID:            w.ID,
		AccountID:     w.AccountID,
		WabaID:        w.WabaID,
		PhoneNumberID: w.PhoneNumberID,
		DisplayPhone:  w.DisplayPhone,
		VerifiedName:  w.VerifiedName,
		Status:        w.Status,
		CreatedAt:     w.CreatedAt,
	}
}

// --- Requests da administração (super-admin) ---

// CreateAccountRequest cria uma empresa e o seu primeiro administrador.
// Os campos da ficha (AccountDetails) são opcionais no cadastro.
type CreateAccountRequest struct {
	Name       string  `json:"name" binding:"required,min=2"`
	Slug       *string `json:"slug" binding:"omitempty"`
	AdminName  string  `json:"admin_name" binding:"required,min=2"`
	AdminEmail string  `json:"admin_email" binding:"required,email"`
	AccountDetails
}

// UpdateAccountRequest edita a empresa (situação + ficha completa).
type UpdateAccountRequest struct {
	Name   *string `json:"name" binding:"omitempty,min=2"`
	Status *string `json:"status" binding:"omitempty,oneof=active suspended canceled"`
	AccountDetails
}

// AddWhatsAppRequest inclui um número na empresa (dados vindos do painel da Meta).
type AddWhatsAppRequest struct {
	WabaID        string  `json:"waba_id" binding:"required"`
	PhoneNumberID string  `json:"phone_number_id" binding:"required"`
	AccessToken   string  `json:"access_token" binding:"required"`
	AppSecret     *string `json:"app_secret"`
	VerifyToken   *string `json:"verify_token"`
	DisplayPhone  *string `json:"display_phone"`
	VerifiedName  *string `json:"verified_name"`
}
