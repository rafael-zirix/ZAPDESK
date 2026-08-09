-- Perfil VENDEDOR: trabalha o funil do CRM (e o atendimento dos seus leads),
-- mas NÃO administra a empresa — plano, cobrança e configurações seguem
-- exclusivos do admin (todas essas rotas exigem RequireAdmin).
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
    CHECK (role IN ('superadmin', 'admin', 'agent', 'vendedor'));
-- Vendedor pertence a uma empresa, como admin/agent (defesa de integridade).
ALTER TABLE users DROP CONSTRAINT users_scope_check;
ALTER TABLE users ADD CONSTRAINT users_scope_check CHECK (
    (role = 'superadmin' AND account_id IS NULL) OR
    (role IN ('admin', 'agent', 'vendedor') AND account_id IS NOT NULL)
);
