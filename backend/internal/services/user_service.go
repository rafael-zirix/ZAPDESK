package services

import (
	"errors"

	"zapdesk/internal/models"
	"zapdesk/internal/repository"
)

var ErrUserNotFound = errors.New("usuário não encontrado")

// UserService gerencia os usuários (atendentes/admins) de uma conta.
type UserService struct{ users *repository.UserRepository }

func NewUserService(users *repository.UserRepository) *UserService {
	return &UserService{users: users}
}

// Create cadastra um usuário na conta.
func (s *UserService) Create(accountID string, req models.CreateUserRequest) (*models.User, error) {
	u := &models.User{
		AccountID: accountID,
		FullName:  req.FullName,
		Email:     req.Email,
		Phone:     req.Phone,
		Role:      req.Role,
		IsActive:  true,
	}
	return s.users.Create(u)
}

// List devolve os usuários da conta.
func (s *UserService) List(accountID string) ([]models.User, error) {
	return s.users.ListByAccount(accountID)
}

// Get devolve um usuário da conta.
func (s *UserService) Get(accountID, id string) (*models.User, error) {
	u, err := s.users.FindByID(accountID, id)
	if err != nil {
		return nil, err
	}
	if u == nil {
		return nil, ErrUserNotFound
	}
	return u, nil
}

// Update altera um usuário da conta.
func (s *UserService) Update(accountID, id string, req models.UpdateUserRequest) (*models.User, error) {
	u, err := s.users.Update(accountID, id, req)
	if err != nil {
		return nil, err
	}
	if u == nil {
		return nil, ErrUserNotFound
	}
	return u, nil
}

// Delete remove (soft) um usuário da conta.
func (s *UserService) Delete(accountID, id string) error {
	ok, err := s.users.SoftDelete(accountID, id)
	if err != nil {
		return err
	}
	if !ok {
		return ErrUserNotFound
	}
	return nil
}
