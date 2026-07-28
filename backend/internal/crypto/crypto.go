// Package crypto cifra segredos em repouso (tokens de WhatsApp das empresas)
// com AES-256-GCM. A chave vem do ambiente (ENCRYPTION_KEY, 32 bytes em hex).
package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"io"
)

// Cipher cifra e decifra strings com AES-256-GCM.
type Cipher struct{ gcm cipher.AEAD }

// New cria o cifrador a partir de uma chave de 32 bytes em hex (64 caracteres).
func New(hexKey string) (*Cipher, error) {
	key, err := hex.DecodeString(hexKey)
	if err != nil {
		return nil, errors.New("ENCRYPTION_KEY inválida (esperado hex)")
	}
	if len(key) != 32 {
		return nil, errors.New("ENCRYPTION_KEY deve ter 32 bytes (64 caracteres hex)")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return &Cipher{gcm: gcm}, nil
}

// Encrypt cifra o texto e devolve base64 (nonce + ciphertext).
func (c *Cipher) Encrypt(plain string) (string, error) {
	nonce := make([]byte, c.gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	sealed := c.gcm.Seal(nonce, nonce, []byte(plain), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt reverte Encrypt.
func (c *Cipher) Decrypt(enc string) (string, error) {
	data, err := base64.StdEncoding.DecodeString(enc)
	if err != nil {
		return "", err
	}
	ns := c.gcm.NonceSize()
	if len(data) < ns {
		return "", errors.New("dado cifrado inválido")
	}
	plain, err := c.gcm.Open(nil, data[:ns], data[ns:], nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}
