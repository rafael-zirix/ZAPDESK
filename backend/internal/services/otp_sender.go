package services

import (
	"errors"
	"log/slog"

	"zapdesk/internal/crypto"
	"zapdesk/internal/repository"
)

// WhatsAppOTPSender envia o código de login por WhatsApp, usando o número
// conectado de uma conta designada (AUTH_OTP_ACCOUNT_ID). Decifra o token
// internamente — ninguém manuseia o token. Requer um template de AUTENTICAÇÃO
// aprovado na Meta.
type WhatsAppOTPSender struct {
	wa        *repository.WhatsAppRepository
	cipher    *crypto.Cipher
	apiBase   string
	accountID string
	template  string
	lang      string
}

func NewWhatsAppOTPSender(wa *repository.WhatsAppRepository, cipher *crypto.Cipher, apiBase, accountID, template, lang string) *WhatsAppOTPSender {
	return &WhatsAppOTPSender{wa: wa, cipher: cipher, apiBase: apiBase, accountID: accountID, template: template, lang: lang}
}

// Configured indica se o canal WhatsApp de OTP está pronto para uso.
func (s *WhatsAppOTPSender) Configured() bool {
	return s != nil && s.accountID != "" && s.cipher != nil && s.wa != nil && s.template != ""
}

// SendOTP manda o código para o telefone (já normalizado, só dígitos) via o
// template de autenticação do número conectado da conta designada.
func (s *WhatsAppOTPSender) SendOTP(phone, code string) error {
	if !s.Configured() {
		return errors.New("canal de OTP por WhatsApp não configurado")
	}
	nums, err := s.wa.ListByAccount(s.accountID)
	if err != nil {
		return err
	}
	for _, w := range nums {
		if w.Status != "connected" {
			continue
		}
		token, err := s.cipher.Decrypt(w.AccessTokenEnc)
		if err != nil {
			return err
		}
		client := NewMetaClient(s.apiBase, token, w.PhoneNumberID)
		id, err := client.SendAuthTemplate(phone, s.template, s.lang, code)
		if err != nil {
			return err
		}
		slog.Info("OTP por WhatsApp aceito pela Meta", "para", phone, "wamid", id,
			"template", s.template, "de_pnid", w.PhoneNumberID)
		return nil
	}
	return errors.New("a conta de OTP não tem número conectado")
}
