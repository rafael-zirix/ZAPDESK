import 'package:flutter/material.dart';

import 'theme.dart';

/// Especificação de um campo do formulário genérico.
class FieldSpec {
  FieldSpec({
    required this.key,
    required this.label,
    this.initial = '',
    this.keyboard,
    this.required = true,
    this.enabled = true,
    this.hint,
    this.options,
    this.section,
  });

  final String key;
  final String label;
  final String initial;
  final TextInputType? keyboard;
  final bool required;
  final bool enabled;
  final String? hint;

  /// Se preenchido, o campo vira um dropdown (value, rótulo).
  final List<(String, String)>? options;

  /// Rótulo de seção exibido ACIMA deste campo (ex.: "Endereço"). Agrupa visualmente.
  final String? section;
}

/// Mostra um formulário em diálogo. `onSubmit` recebe os valores e devolve uma
/// mensagem de erro (para exibir) ou null em caso de sucesso. Retorna true se
/// salvou.
Future<bool> showEntityForm(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required Future<String?> Function(Map<String, String> values) onSubmit,
  String submitLabel = 'Salvar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EntityFormDialog(title: title, fields: fields, onSubmit: onSubmit, submitLabel: submitLabel),
  );
  return result ?? false;
}

class _EntityFormDialog extends StatefulWidget {
  const _EntityFormDialog({required this.title, required this.fields, required this.onSubmit, required this.submitLabel});
  final String title;
  final List<FieldSpec> fields;
  final Future<String?> Function(Map<String, String>) onSubmit;
  final String submitLabel;

  @override
  State<_EntityFormDialog> createState() => _EntityFormDialogState();
}

class _EntityFormDialogState extends State<_EntityFormDialog> {
  late final Map<String, TextEditingController> _text;
  late final Map<String, String> _selects;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = {
      for (final f in widget.fields.where((f) => f.options == null)) f.key: TextEditingController(text: f.initial),
    };
    _selects = {
      for (final f in widget.fields.where((f) => f.options != null))
        f.key: f.initial.isNotEmpty ? f.initial : f.options!.first.$1,
    };
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final values = <String, String>{};
    for (final f in widget.fields) {
      final v = f.options != null ? (_selects[f.key] ?? '') : _text[f.key]!.text.trim();
      if (f.required && v.isEmpty) {
        setState(() => _error = 'Preencha o campo "${f.label}"');
        return;
      }
      values[f.key] = v;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onSubmit(values);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final f in widget.fields) ...[
                if (f.section != null) _sectionLabel(f.section!),
                _field(f),
                const SizedBox(height: 14),
              ],
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(110, 44)),
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.submitLabel),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.5)),
      );

  Widget _field(FieldSpec f) {
    if (f.options != null) {
      return DropdownButtonFormField<String>(
        initialValue: _selects[f.key],
        decoration: InputDecoration(labelText: f.label),
        items: [for (final o in f.options!) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
        onChanged: f.enabled ? (v) => setState(() => _selects[f.key] = v ?? '') : null,
      );
    }
    return TextField(
      controller: _text[f.key],
      enabled: f.enabled,
      keyboardType: f.keyboard,
      decoration: InputDecoration(labelText: f.label, hintText: f.hint),
      onSubmitted: (_) => _submit(),
    );
  }
}

/// Cabeçalho padrão das telas de cadastro: título + botão de ação à direita.
class ListHeader extends StatelessWidget {
  const ListHeader({super.key, required this.title, this.actionLabel, this.onAction});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (actionLabel != null)
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add, size: 20),
              label: Text(actionLabel!),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.seed,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
        ],
      ),
    );
  }
}
