import 'package:flutter/material.dart';

import 'theme_mobile.dart';

/// Avatar circular com as iniciais e um selo do canal (WhatsApp/Instagram) — o
/// atendente precisa saber por onde o cliente chegou antes de responder, porque
/// no Instagram não existe modelo aprovado para reabrir a conversa.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.channel = 'whatsapp', this.size = 44});

  final String name;
  final String channel;
  final double size;

  String get _initials {
    final s = name.trim();
    if (s.isEmpty) return '?';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.4;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: MobileTheme.avatarColor(name), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w600),
            ),
          ),
          if (channel == 'instagram')
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: badge,
                height: badge,
                decoration: BoxDecoration(
                  color: const Color(0xFFC13584), // roxo do Instagram
                  shape: BoxShape.circle,
                  border: Border.all(color: MobileTheme.listBg, width: 1.6),
                ),
                child: Icon(Icons.camera_alt, size: badge * 0.55, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip pequeno de status/etiqueta/setor usado na lista e no cabeçalho.
class MiniChip extends StatelessWidget {
  const MiniChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Fundo cheio em vez de suave — para o "Novo" saltar aos olhos.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final bg = filled ? color : color.withValues(alpha: 0.15);
    final fg = filled ? Colors.white : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 7 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.3,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Converte "#0E9384" (ou "0E9384") na cor. Cai no teal da marca se vier torto —
/// uma etiqueta com cor inválida não deve derrubar a lista.
Color hexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? MobileTheme.brand : Color(v);
}

/// SnackBar padrão do app.
void toast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? const Color(0xFFB42318) : null,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Diálogo sim/não. Devolve true se confirmou.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? detail,
  required String action,
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: detail == null ? null : Text(detail),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: destructive ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)) : null,
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Cabeçalho padrão dos bottom sheets (alça + título).
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.label, {super.key, this.action});
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: MobileTheme.textFaint.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: MobileTheme.text)),
              ),
              ?action,
            ],
          ),
        ),
      ],
    );
  }
}
