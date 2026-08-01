/// Um contato lido de um arquivo de importação.
typedef ImportedContact = ({String name, String phone});

/// Decide entre vCard e CSV pela extensão/conteúdo e faz o parse.
List<ImportedContact> parseContactsFile(String filename, String content) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.vcf') || content.toUpperCase().contains('BEGIN:VCARD')) {
    return _parseVCard(content);
  }
  return _parseCsv(content);
}

/// vCard (.vcf): um contato por BEGIN/END:VCARD; usa FN (nome) e o 1º TEL.
List<ImportedContact> _parseVCard(String content) {
  final out = <ImportedContact>[];
  for (final card in content.split(RegExp(r'END:VCARD', caseSensitive: false))) {
    if (!card.toUpperCase().contains('BEGIN:VCARD')) continue;
    String name = '', phone = '';
    for (final raw in card.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      final up = line.toUpperCase();
      if (name.isEmpty && up.startsWith('FN')) {
        final i = line.indexOf(':');
        if (i >= 0) name = line.substring(i + 1).trim();
      } else if (phone.isEmpty && up.startsWith('TEL')) {
        final i = line.indexOf(':');
        if (i >= 0) phone = line.substring(i + 1).trim();
      }
    }
    if (phone.isNotEmpty) out.add((name: name.isEmpty ? phone : name, phone: phone));
  }
  return out;
}

/// CSV: detecta as colunas de nome e telefone pelo cabeçalho (pt/en). Sem
/// cabeçalho reconhecível, assume coluna 0 = nome e coluna 1 = telefone.
List<ImportedContact> _parseCsv(String content) {
  final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return [];
  final sep = lines.first.contains(';') && !lines.first.contains(',') ? ';' : ',';
  final header = _splitCsv(lines.first, sep).map((h) => h.toLowerCase().trim()).toList();

  int nameIdx = header.indexWhere((h) => h.contains('name') || h.contains('nome'));
  int phoneIdx = header.indexWhere((h) =>
      h.contains('phone') || h.contains('telefone') || h.contains('tel') || h.contains('celular') ||
      h.contains('mobile') || h.contains('número') || h.contains('numero') || h.contains('whatsapp'));

  final hasHeader = nameIdx >= 0 || phoneIdx >= 0;
  if (!hasHeader) {
    nameIdx = 0;
    phoneIdx = 1;
  }

  final out = <ImportedContact>[];
  for (var i = hasHeader ? 1 : 0; i < lines.length; i++) {
    final cols = _splitCsv(lines[i], sep);
    final name = (nameIdx >= 0 && nameIdx < cols.length) ? cols[nameIdx].trim() : '';
    final phone = (phoneIdx >= 0 && phoneIdx < cols.length) ? cols[phoneIdx].trim() : '';
    if (phone.isNotEmpty) out.add((name: name.isEmpty ? phone : name, phone: phone));
  }
  return out;
}

/// Split de uma linha CSV respeitando aspas duplas.
List<String> _splitCsv(String line, String sep) {
  final out = <String>[];
  final sb = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == sep && !quoted) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out;
}
