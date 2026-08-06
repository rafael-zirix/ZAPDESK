-- Campanhas com template de VARIÁVEIS ({{1}}, {{2}}…) e FOTO no cabeçalho.
-- params: JSON array com um valor por variável ({nome} vira o nome do contato).
-- image_url: URL pública da foto (modelos com header de imagem aprovado na Meta).
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS params TEXT;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS image_url TEXT;
