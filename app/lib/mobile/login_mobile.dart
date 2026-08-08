import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';
import 'theme_mobile.dart';

/// Login do app: o mesmo OTP em duas etapas do painel. O atendente digita
/// e-mail OU celular; o código chega por e-mail ou pelo WhatsApp, conforme o
/// que ele informou (quem decide é o backend).
class LoginMobile extends StatefulWidget {
  const LoginMobile({super.key});

  @override
  State<LoginMobile> createState() => _LoginMobileState();
}

class _LoginMobileState extends State<LoginMobile> {
  final _id = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  @override
  void dispose() {
    _id.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Só dígitos (com ou sem +) = celular → o código vai pelo WhatsApp.
  bool get _pareceTelefone {
    final t = _id.text.trim();
    if (t.isEmpty || t.contains('@')) return false;
    return RegExp(r'^\+?[\d\s()\-]{8,}$').hasMatch(t);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final aguardandoCodigo = auth.status == AuthStatus.awaitingCode;

    return Scaffold(
      backgroundColor: MobileTheme.appBar,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Marca(),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    decoration: BoxDecoration(
                      color: MobileTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: aguardandoCodigo ? _etapaCodigo(auth) : _etapaIdentificador(auth),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Atendimento HotZap',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _etapaIdentificador(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Entrar',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MobileTheme.text)),
        const SizedBox(height: 6),
        Text('Informe seu e-mail ou o celular cadastrado. Enviamos um código de acesso.',
            style: TextStyle(color: MobileTheme.textFaint, fontSize: 13.5, height: 1.35)),
        const SizedBox(height: 20),
        TextField(
          controller: _id,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.go,
          style: TextStyle(color: MobileTheme.text),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _pedirCodigo(auth),
          decoration: InputDecoration(
            labelText: 'E-mail ou celular',
            prefixIcon: Icon(_pareceTelefone ? Icons.smartphone : Icons.alternate_email),
            filled: true,
            fillColor: MobileTheme.composerField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: MobileTheme.border),
            ),
          ),
        ),
        if (_pareceTelefone) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.chat_bubble, size: 15, color: Color(0xFF25D366)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('O código chega no seu WhatsApp',
                    style: TextStyle(color: MobileTheme.textFaint, fontSize: 12.5)),
              ),
            ],
          ),
        ],
        if (auth.error != null) ...[
          const SizedBox(height: 12),
          _Erro(auth.error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: auth.busy || _id.text.trim().isEmpty ? null : () => _pedirCodigo(auth),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: auth.busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Receber código', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _etapaCodigo(AuthController auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: auth.busy ? null : auth.backToEmail,
              icon: const Icon(Icons.arrow_back),
              color: MobileTheme.text,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Código de acesso',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: MobileTheme.text)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Enviado para ${auth.pendingIdentifier ?? ''}',
            style: TextStyle(color: MobileTheme.textFaint, fontSize: 13.5)),
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          focusNode: _codeFocus,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700, color: MobileTheme.text),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: TextStyle(letterSpacing: 10, color: MobileTheme.textFaint.withValues(alpha: 0.5)),
            filled: true,
            fillColor: MobileTheme.composerField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: MobileTheme.border),
            ),
          ),
          // 6 dígitos = envia sozinho, sem o atendente procurar o botão.
          onChanged: (v) {
            if (v.length == 6 && !auth.busy) auth.verifyCode(v);
          },
        ),
        if (auth.error != null) ...[
          const SizedBox(height: 12),
          _Erro(auth.error!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: auth.busy || _code.text.length < 4 ? null : () => auth.verifyCode(_code.text),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: auth.busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Entrar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: auth.busy
              ? null
              : () {
                  _code.clear();
                  auth.requestCode(auth.pendingIdentifier ?? '');
                },
          child: const Text('Reenviar código'),
        ),
      ],
    );
  }

  void _pedirCodigo(AuthController auth) {
    final id = _id.text.trim();
    if (id.isEmpty) return;
    _code.clear();
    auth.requestCode(id);
  }
}

class _Marca extends StatelessWidget {
  const _Marca();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.chat_bubble_rounded, size: 40, color: MobileTheme.brand),
        ),
        const SizedBox(height: 14),
        const Text('HotZap',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.5)),
      ],
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF5C6C6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 17, color: Color(0xFFB42318)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(color: Color(0xFFB42318), fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
