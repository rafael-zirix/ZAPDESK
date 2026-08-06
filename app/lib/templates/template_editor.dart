import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/file_pick.dart';
import '../core/theme.dart';

/// Editor de MODELO (template) da Meta: o cliente monta cabeçalho (texto ou
/// FOTO), corpo com variáveis {{n}}, rodapé e botões — com prévia ao vivo — e
/// nós enviamos para a aprovação da Meta.
///
/// Regras da Meta embutidas aqui (evitam rejeição):
///  • nome em minúsculas_com_underscore (normalizado no backend);
///  • toda variável {{n}} precisa de um EXEMPLO na criação;
///  • cabeçalho de imagem exige uma imagem de exemplo (upload → handle);
///  • categoria certa: Marketing (promoção) × Utilidade (aviso de serviço).
class TemplateEditor extends StatefulWidget {
  const TemplateEditor({super.key});

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  final _api = ApiClient.instance;

  final name = TextEditingController();
  final body = TextEditingController();
  final headerText = TextEditingController();
  final footer = TextEditingController();
  final buttonCtrls = <TextEditingController>[];
  final exampleCtrls = <TextEditingController>[];

  String category = 'MARKETING';
  String headerType = 'NONE'; // NONE | TEXT | IMAGE
  String? imageHandle;
  String? imageName;
  bool uploading = false;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    body.addListener(_syncExamples);
  }

  @override
  void dispose() {
    name.dispose();
    body.dispose();
    headerText.dispose();
    footer.dispose();
    for (final c in [...buttonCtrls, ...exampleCtrls]) {
      c.dispose();
    }
    super.dispose();
  }

  int get varCount {
    var max = 0;
    for (final m in RegExp(r'\{\{(\d+)\}\}').allMatches(body.text)) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > max) max = n;
    }
    return max;
  }

  void _syncExamples() {
    final n = varCount;
    var changed = false;
    while (exampleCtrls.length < n) {
      exampleCtrls.add(TextEditingController());
      changed = true;
    }
    while (exampleCtrls.length > n) {
      exampleCtrls.removeLast().dispose();
      changed = true;
    }
    if (changed || mounted) setState(() {});
  }

  /// Insere a próxima variável na posição do cursor do corpo.
  void _insertVar() {
    final n = varCount + 1;
    final sel = body.selection;
    final text = body.text;
    final at = sel.isValid ? sel.start : text.length;
    body.text = '${text.substring(0, at)}{{$n}}${text.substring(sel.isValid ? sel.end : text.length)}';
    body.selection = TextSelection.collapsed(offset: at + '{{$n}}'.length);
  }

  Future<void> _pickImage() async {
    final f = await pickFile(accept: 'image/png,image/jpeg');
    if (f == null) return;
    setState(() => uploading = true);
    final r = await _api.uploadFile('/support/templates/image',
        bytes: f.bytes, filename: f.name, contentType: f.mimeType);
    if (!mounted) return;
    setState(() {
      uploading = false;
      if (r.ok && r.data is Map) {
        imageHandle = (r.data as Map)['handle'] as String?;
        imageName = f.name;
      } else {
        error = r.message ?? 'Não foi possível enviar a imagem';
      }
    });
  }

  Future<void> _submit() async {
    setState(() => error = null);
    if (name.text.trim().length < 3) {
      setState(() => error = 'Dê um nome ao modelo (mín. 3 letras)');
      return;
    }
    if (body.text.trim().isEmpty) {
      setState(() => error = 'Escreva a mensagem do modelo');
      return;
    }
    if (headerType == 'IMAGE' && imageHandle == null) {
      setState(() => error = 'Envie a imagem do cabeçalho');
      return;
    }
    if (exampleCtrls.any((c) => c.text.trim().isEmpty)) {
      setState(() => error = 'Preencha um exemplo para cada variável — a Meta exige isso na aprovação');
      return;
    }
    setState(() => saving = true);
    final r = await _api.post('/support/templates/full', {
      'name': name.text.trim(),
      'language': 'pt_BR',
      'category': category,
      'header_type': headerType == 'NONE' ? '' : headerType,
      if (headerType == 'TEXT') 'header_text': headerText.text.trim(),
      if (headerType == 'IMAGE') 'header_handle': imageHandle,
      'body': body.text.trim(),
      'body_examples': [for (final c in exampleCtrls) c.text.trim()],
      if (footer.text.trim().isNotEmpty) 'footer': footer.text.trim(),
      'buttons': [
        for (final b in buttonCtrls)
          if (b.text.trim().isNotEmpty) {'type': 'QUICK_REPLY', 'text': b.text.trim()},
      ],
    });
    if (!mounted) return;
    setState(() => saving = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => error = r.message ?? 'A Meta recusou o modelo');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo modelo de mensagem'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, cons) {
              final wide = cons.maxWidth > 620;
              final formW = wide ? cons.maxWidth - 280 : cons.maxWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: formW, child: _form()),
                  if (wide) SizedBox(width: 280, child: _preview()),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
          onPressed: saving ? null : _submit,
          icon: saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_outlined, size: 18),
          label: const Text('Enviar para aprovação'),
        ),
      ],
    );
  }

  Widget _form() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Nome do modelo',
              hintText: 'ex.: promocao_agosto',
              helperText: 'Só para você identificar. O cliente não vê.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: category,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder(), isDense: true),
            items: const [
              DropdownMenuItem(value: 'MARKETING', child: Text('Marketing — promoção, novidade, convite')),
              DropdownMenuItem(value: 'UTILITY', child: Text('Utilidade — aviso sobre algo que o cliente contratou')),
            ],
            onChanged: (v) => setState(() => category = v ?? 'MARKETING'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              category == 'MARKETING'
                  ? 'Marketing: qualquer oferta ou divulgação. Custa mais por conversa.'
                  : 'Utilidade: aviso de pedido, cobrança, agendamento… Só para quem já é cliente — a Meta rejeita promoção aqui.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Cabeçalho (opcional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'NONE', label: Text('Nenhum')),
              ButtonSegment(value: 'TEXT', label: Text('Texto')),
              ButtonSegment(value: 'IMAGE', label: Text('Foto')),
            ],
            selected: {headerType},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => headerType = s.first),
          ),
          if (headerType == 'TEXT') ...[
            const SizedBox(height: 10),
            TextField(
              controller: headerText,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Título',
                hintText: 'ex.: Oferta da semana',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          if (headerType == 'IMAGE') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: uploading ? null : _pickImage,
                  icon: uploading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined, size: 18),
                  label: Text(imageHandle == null ? 'Enviar imagem de exemplo' : 'Trocar imagem'),
                ),
                const SizedBox(width: 8),
                if (imageHandle != null)
                  const Icon(Icons.check_circle, size: 18, color: Color(0xFF1F9D57)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                imageName != null
                    ? 'Imagem enviada: $imageName'
                    : 'A Meta pede uma imagem de exemplo para revisar o modelo. Em cada campanha você escolhe a foto real.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Mensagem', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                onPressed: _insertVar,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Inserir variável'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          TextField(
            controller: body,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'Olá {{1}}! Temos uma novidade para você…',
              border: OutlineInputBorder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Use *negrito*, _itálico_ e variáveis {{1}}, {{2}}… para personalizar por contato.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ),
          if (exampleCtrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Exemplos das variáveis', style: TextStyle(fontWeight: FontWeight.w600)),
            Text('Obrigatório: é o que o revisor da Meta vê para entender a mensagem.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            for (var i = 0; i < exampleCtrls.length; i++) ...[
              const SizedBox(height: 8),
              TextField(
                controller: exampleCtrls[i],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Exemplo de {{${i + 1}}}',
                  hintText: i == 0 ? 'ex.: Maria' : 'ex.: 20% de desconto',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          TextField(
            controller: footer,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Rodapé (opcional)',
              hintText: 'ex.: Responda SAIR para não receber mais',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Botões (opcional)', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (buttonCtrls.length < 3)
                TextButton.icon(
                  onPressed: () => setState(() => buttonCtrls.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Adicionar'),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.seed, visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          for (var i = 0; i < buttonCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: buttonCtrls[i],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Texto do botão',
                        hintText: 'ex.: Quero saber mais',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => buttonCtrls.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
          if (buttonCtrls.isEmpty)
            Text('Um botão "Parar promoções" reduz bloqueios e protege a qualidade do seu número.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
              ),
              child: Text(error!, style: const TextStyle(fontSize: 12.5, color: Color(0xFFB42318))),
            ),
          ],
        ],
      ),
    );
  }

  /// Prévia estilo WhatsApp (balão verde-claro), com as variáveis substituídas
  /// pelos exemplos digitados.
  Widget _preview() {
    var text = body.text.isEmpty ? 'Sua mensagem aparece aqui…' : body.text;
    for (var i = 0; i < exampleCtrls.length; i++) {
      final v = exampleCtrls[i].text.trim();
      if (v.isNotEmpty) text = text.replaceAll('{{${i + 1}}}', v);
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Prévia', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFDCF8C6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (headerType == 'IMAGE')
                  Container(
                    height: 96,
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.image_outlined, color: Colors.black.withValues(alpha: 0.35)),
                  ),
                if (headerType == 'TEXT' && headerText.text.trim().isNotEmpty) ...[
                  Text(headerText.text.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87)),
                  const SizedBox(height: 4),
                ],
                Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35, color: Colors.black87)),
                if (footer.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(footer.text.trim(),
                      style: TextStyle(fontSize: 11.5, color: Colors.black.withValues(alpha: 0.45))),
                ],
              ],
            ),
          ),
          for (final b in buttonCtrls)
            if (b.text.trim().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text(b.text.trim(),
                    style: const TextStyle(color: Color(0xFF00A5F4), fontSize: 13, fontWeight: FontWeight.w600)),
              ),
          const SizedBox(height: 10),
          Text('A Meta revisa em minutos (às vezes horas). O status aparece na lista.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.3)),
        ],
      ),
    );
  }
}
