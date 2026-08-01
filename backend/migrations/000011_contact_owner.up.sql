-- Dono do contato: cada usuário vê os seus. Contatos sem dono (legados e os
-- criados pelo webhook a partir de mensagens recebidas) ficam compartilhados.
ALTER TABLE support_contacts ADD COLUMN IF NOT EXISTS owner_user_id UUID;
CREATE INDEX IF NOT EXISTS idx_support_contacts_owner ON support_contacts(account_id, owner_user_id);
