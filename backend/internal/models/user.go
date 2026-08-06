package models

import "time"

// Papéis de usuário.
const (
	RoleSuperadmin = "superadmin" // dono da plataforma (SaaS), sem conta
	RoleAdmin      = "admin"      // administra uma empresa
	RoleAgent      = "agent"      // atendente de uma empresa
)

// User é um atendente ou administrador de uma conta (empresa cliente do SaaS).
type User struct {
	ID        string
	AccountID string
	FullName  string
	Email     *string
	Phone     *string
	Role      string
	IsActive  bool
	Presence  string // available | away (informativo; insumo da distribuição futura)
	CreatedAt time.Time
	UpdatedAt time.Time
	DeletedAt *time.Time
}

// IsAdmin indica se o usuário administra a conta.
func (u *User) IsAdmin() bool { return u.Role == RoleAdmin }

// IsSuperAdmin indica se o usuário é dono da plataforma (SaaS).
func (u *User) IsSuperAdmin() bool { return u.Role == RoleSuperadmin }

// CreateUserRequest é o corpo para criar um usuário.
type CreateUserRequest struct {
	FullName string  `json:"full_name" binding:"required,min=2"`
	Email    *string `json:"email" binding:"omitempty,email"`
	Phone    *string `json:"phone" binding:"omitempty"`
	Role     string  `json:"role" binding:"required,oneof=admin agent"`
}

// UpdateUserRequest é o corpo para atualizar um usuário (campos opcionais).
type UpdateUserRequest struct {
	FullName *string `json:"full_name" binding:"omitempty,min=2"`
	Email    *string `json:"email" binding:"omitempty,email"`
	Phone    *string `json:"phone" binding:"omitempty"`
	Role     *string `json:"role" binding:"omitempty,oneof=admin agent"`
	IsActive *bool   `json:"is_active"`
}

// UserResponse é a representação pública de um usuário.
type UserResponse struct {
	ID        string    `json:"id"`
	AccountID string    `json:"account_id"`
	FullName  string    `json:"full_name"`
	Email     *string   `json:"email,omitempty"`
	Phone     *string   `json:"phone,omitempty"`
	Role      string    `json:"role"`
	IsActive  bool      `json:"is_active"`
	Presence  string    `json:"presence"`
	CreatedAt time.Time `json:"created_at"`
}

// ToResponse converte o modelo para a resposta pública.
func (u *User) ToResponse() UserResponse {
	return UserResponse{
		ID:        u.ID,
		AccountID: u.AccountID,
		FullName:  u.FullName,
		Email:     u.Email,
		Phone:     u.Phone,
		Role:      u.Role,
		IsActive:  u.IsActive,
		Presence:  u.Presence,
		CreatedAt: u.CreatedAt,
	}
}
