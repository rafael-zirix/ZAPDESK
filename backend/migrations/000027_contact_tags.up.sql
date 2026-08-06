-- Etiquetas no CONTATO (além das conversas). A etiqueta na conversa é volátil
-- (a conversa fecha e nasce outra); no contato ela é permanente — por isso vira
-- um filtro melhor para campanhas.
--
-- Reusa a mesma tabela support_tags: a empresa cadastra a etiqueta uma vez e
-- pode aplicá-la tanto à conversa quanto ao contato.
CREATE TABLE contact_tags (
    contact_id UUID NOT NULL REFERENCES support_contacts(id) ON DELETE CASCADE,
    tag_id     UUID NOT NULL REFERENCES support_tags(id) ON DELETE CASCADE,
    PRIMARY KEY (contact_id, tag_id)
);
CREATE INDEX idx_contact_tags_tag ON contact_tags (tag_id);
