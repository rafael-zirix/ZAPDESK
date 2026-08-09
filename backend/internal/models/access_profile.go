package models

// Perm é a dupla ver/gravar de uma função do sistema.
type Perm struct {
	View  bool `json:"view"`
	Write bool `json:"write"`
}

// AccessProfile é um perfil de acesso criado pelo admin da empresa.
type AccessProfile struct {
	ID        string          `json:"id"`
	AccountID string          `json:"-"`
	Name      string          `json:"name"`
	Perms     map[string]Perm `json:"perms"`
	Users     []string        `json:"user_ids"` // quem usa este perfil (exibição)
}

// AccessProfileRequest cria/edita um perfil (as permissões substituem as atuais).
type AccessProfileRequest struct {
	Name  string          `json:"name" binding:"required,min=1"`
	Perms map[string]Perm `json:"perms"`
}

// PermDef é um item do catálogo (uma função do sistema na árvore).
type PermDef struct {
	Key      string `json:"key"`
	Label    string `json:"label"`
	HasWrite bool   `json:"has_write"` // false = função só de leitura (ex.: métricas)
}

// PermGroup é um ramo da árvore (espelha um agrupamento do menu).
type PermGroup struct {
	Label string    `json:"label"`
	Items []PermDef `json:"items"`
}
