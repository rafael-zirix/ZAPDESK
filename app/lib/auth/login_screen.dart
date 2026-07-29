import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import 'auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final awaiting = auth.status == AuthStatus.awaitingCode;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _logo(),
                const SizedBox(height: 24),
                Text(
                  awaiting ? 'Digite o código' : 'Entrar',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  awaiting
                      ? 'Enviamos um código para\n${auth.pendingIdentifier}'
                      : 'Acesse o painel de atendimento',
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!awaiting) ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    onSubmitted: (_) => _submitEmail(auth),
                  ),
                ] else ...[
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(hintText: '000000', counterText: ''),
                    maxLength: 6,
                    onSubmitted: (_) => _submitCode(auth),
                  ),
                ],
                if (auth.error != null) ...[
                  const SizedBox(height: 12),
                  Text(auth.error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: auth.busy ? null : () => awaiting ? _submitCode(auth) : _submitEmail(auth),
                  child: auth.busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(awaiting ? 'Confirmar' : 'Enviar código'),
                ),
                if (awaiting) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: auth.busy ? null : auth.backToEmail,
                    child: const Text('Usar outro e-mail'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.seed,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 12),
        const Text('Zapdesk', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ],
    );
  }

  void _submitEmail(AuthController auth) {
    if (_email.text.trim().isEmpty) return;
    auth.requestCode(_email.text);
  }

  void _submitCode(AuthController auth) {
    if (_code.text.trim().length < 4) return;
    auth.verifyCode(_code.text);
  }
}
