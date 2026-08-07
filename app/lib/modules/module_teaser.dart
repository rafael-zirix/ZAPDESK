import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/app_module.dart';

/// Vitrine de um módulo que a empresa ainda não contratou. É UMA tela genérica
/// para todos os módulos — o conteúdo vem do catálogo do backend.
class ModuleTeaserScreen extends StatefulWidget {
  const ModuleTeaserScreen({super.key, required this.moduleKey});

  final String moduleKey;

  @override
  State<ModuleTeaserScreen> createState() => _ModuleTeaserScreenState();
}

class _ModuleTeaserScreenState extends State<ModuleTeaserScreen> {
  bool sending = false;
  bool sent = false;

  Future<void> _quero(AppModule m) async {
    setState(() => sending = true);
    final r = await ApiClient.instance.post('/modules/${m.key}/interest', const <String, dynamic>{});
    if (!mounted) return;
    setState(() {
      sending = false;
      sent = r.ok;
    });
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.message ?? 'Não foi possível registrar o pedido')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final m = auth.module(widget.moduleKey);
    if (m == null) return const SizedBox.shrink();
    final isAdmin = auth.me?.isAdmin ?? false;
    return Container(
      color: AppTheme.bg,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: SizedBox(
          width: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.seed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(m.comingSoon ? 'EM BREVE' : 'MÓDULO',
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppTheme.seed)),
                    ),
                    const SizedBox(height: 14),
                    Text(m.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(m.description,
                        style: TextStyle(fontSize: 14.5, height: 1.45, color: Colors.grey.shade700)),
                    const SizedBox(height: 20),
                    if (!m.comingSoon)
                      Text(m.priceLabel,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.seed)),
                    const SizedBox(height: 20),
                    if (sent)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF1F9D57), size: 20),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 380,
                            child: Text(
                                m.comingSoon
                                    ? 'Anotado! Avisamos assim que este módulo estiver disponível.'
                                    : 'Pedido registrado. Nossa equipe libera o módulo e fala com você.',
                                style: TextStyle(color: Colors.grey.shade700)),
                          ),
                        ],
                      )
                    else if (isAdmin)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppTheme.seed),
                        onPressed: sending ? null : () => _quero(m),
                        icon: sending
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.shopping_bag_outlined, size: 18),
                        label: Text(m.comingSoon ? 'Tenho interesse' : 'Quero contratar'),
                      )
                    else
                      Text('Fale com o administrador da sua empresa para contratar.',
                          style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Módulos ficam disponíveis na hora da contratação — nada é reinstalado nem reconfigurado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }
}
