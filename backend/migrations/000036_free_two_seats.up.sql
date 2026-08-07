-- Free passa a ter 2 atendentes (era 3): a maioria das PMEs cabia em 3 e a
-- conversão ficava só na IA. Vale para contas NOVAS — quem já entrou com 3
-- mantém os 3, porque tirar assento de quem já está usando é quebra de acordo.
ALTER TABLE accounts ALTER COLUMN max_users SET DEFAULT 2;
