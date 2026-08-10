import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/crm.dart';
import 'crm_controller.dart';
import 'crm_format.dart';

/// Gestão das etapas do Kanban (admin): criar, renomear, cor, ordem, excluir.
Future<void> showStageEditor(BuildContext context, CrmController crm) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _StageEditorDialog(crm: crm),
  );
}

class _StageEditorDialog extends StatefulWidget {
  const _StageEditorDialog({required this.crm});
  final CrmController crm;

  @override
  State<_StageEditorDialog> createState() => _StageEditorDialogState();
}

class _StageEditorDialogState extends State<_StageEditorDialog> {
  final _newName = TextEditingController();
  String _newColor = kStagePalette.first;
  String? _error;
  bool _busy = false;

  CrmController get crm => widget.crm;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stages = [...crm.stages]..sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return AlertDialog(
      title: const Text('Etapas do funil'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A primeira etapa recebe os leads; a marcada com 🏆 fecha o negócio como ganho.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            const SizedBox(height: 10),
            SizedBox(
              height: 320,
              child: ListView(
                children: [for (final s in stages) _row(s, stages)],
              ),
            ),
            const Divider(height: 20),
            Row(children: [
              _colorPicker(_newColor, (c) => setState(() => _newColor = c)),
              const SizedBox(width: 8),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _newName,
                  decoration: const InputDecoration(hintText: 'Nova etapa…', isDense: true),
                  onSubmitted: (_) => _create(),
                ),
              ),
              const SizedBox(width: 8),
              // FilledButton some no CanvasKit em Row (sonda) — botão custom.
              crmButton(
                onTap: () { if (!_busy) _create(); },
                icon: Icons.add,
                label: 'Criar',
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    await _run(() => crm.createStage(name, _newColor));
    if (_error == null) _newName.clear();
  }

  Widget _row(CrmStage s, List<CrmStage> sorted) {
    final first = sorted.first.id == s.id;
    final last = sorted.last.id == s.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        _colorPicker(s.color, (c) => _run(() => crm.updateStage(s.id, {'color': c}))),
        const SizedBox(width: 8),
        SizedBox(
          width: 210,
          child: _StageNameField(
            key: ValueKey('${s.id}:${s.name}'),
            initial: s.name,
            enabled: !_busy,
            onRename: (name) => _run(() => crm.updateStage(s.id, {'name': name})),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 26,
          child: s.isWon
              ? const Tooltip(message: 'Etapa de ganho', child: Text('🏆', style: TextStyle(fontSize: 15)))
              : (s.isSystem
                  ? Tooltip(
                      message: 'Etapa de entrada (leads caem aqui)',
                      child: Icon(Icons.login, size: 16, color: Colors.grey.shade500))
                  : const SizedBox.shrink()),
        ),
        IconButton(
          tooltip: 'Subir',
          onPressed: _busy || first ? null : () => _run(() => crm.reorderStage(s, -1)),
          icon: const Icon(Icons.arrow_upward, size: 17),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Descer',
          onPressed: _busy || last ? null : () => _run(() => crm.reorderStage(s, 1)),
          icon: const Icon(Icons.arrow_downward, size: 17),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: s.isSystem ? 'Etapa do sistema não pode ser excluída' : 'Excluir',
          onPressed: _busy || s.isSystem ? null : () => _confirmDelete(s),
          icon: Icon(Icons.delete_outline,
              size: 17, color: s.isSystem ? Colors.grey.shade400 : const Color(0xFFEF4444)),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(CrmStage s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir "${s.name}"?'),
        content: const Text('Só é possível excluir etapa sem negócios.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => crm.deleteStage(s.id));
  }

  Widget _colorPicker(String current, void Function(String) onPick) {
    return PopupMenuButton<String>(
      tooltip: 'Cor',
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final c in kStagePalette)
          PopupMenuItem(
            value: c,
            height: 34,
            child: Row(children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: hexColor(c), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(c, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
      ],
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: hexColor(current),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.border, width: 2),
        ),
      ),
    );
  }
}

/// Campo de nome com edição inline: salva no Enter ou ao perder o foco.
class _StageNameField extends StatefulWidget {
  const _StageNameField({super.key, required this.initial, required this.enabled, required this.onRename});
  final String initial;
  final bool enabled;
  final void Function(String) onRename;

  @override
  State<_StageNameField> createState() => _StageNameFieldState();
}

class _StageNameFieldState extends State<_StageNameField> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _maybeRename();
    });

  void _maybeRename() {
    final v = _c.text.trim();
    if (v.isNotEmpty && v != widget.initial) widget.onRename(v);
  }

  @override
  void dispose() {
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      enabled: widget.enabled,
      decoration: const InputDecoration(isDense: true, border: InputBorder.none),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      onSubmitted: (_) => _maybeRename(),
    );
  }
}
