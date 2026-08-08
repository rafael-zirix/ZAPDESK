-- Troca de IA agendada: o cliente escolhe usar o saldo atual e só então mudar de
-- modelo. O modelo destino fica "pendente" até o saldo zerar; nesse momento o
-- consumo aplica a troca sozinho (ver moveTokens). NULL = nenhuma troca agendada.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS pending_ai_model TEXT;
