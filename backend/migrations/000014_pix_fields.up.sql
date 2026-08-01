-- Campos do PIX (Mercado Pago) no pedido de recarga: o copia-e-cola e a imagem
-- do QR (base64), para o app mostrar ao cliente sem ir a outra página.
ALTER TABLE token_orders ADD COLUMN IF NOT EXISTS pix_qr TEXT;
ALTER TABLE token_orders ADD COLUMN IF NOT EXISTS pix_qr_base64 TEXT;
