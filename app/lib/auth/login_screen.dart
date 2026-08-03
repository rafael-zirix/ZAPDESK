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
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _company = TextEditingController();
  final _name = TextEditingController();

  // Login por celular (padrão, código no WhatsApp) ou por e-mail (reserva).
  bool _useEmail = false;
  // Modo de auto-cadastro (empresa + nome + WhatsApp), vindo de ?signup=1.
  bool _signupMode = false;

  @override
  void initState() {
    super.initState();
    // Vindo da landing (/start.html): ?signup=1 abre o cadastro; ?phone= /
    // ?email= pré-preenchem o identificador (o cliente não digita duas vezes).
    final q = Uri.base.queryParameters;
    final phone = (q['phone'] ?? '').trim();
    final email = (q['email'] ?? '').trim();
    if (email.isNotEmpty) {
      _useEmail = true;
      _email.text = email;
    } else if (phone.isNotEmpty) {
      _phone.text = phone;
    }
    if (q['signup'] == '1') _signupMode = true;
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    _company.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final awaiting = auth.status == AuthStatus.awaitingCode;
    final pending = auth.pendingIdentifier ?? '';
    final viaWhats = !pending.contains('@');

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
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
                  awaiting ? 'Digite o código' : (_signupMode ? 'Criar sua conta' : 'Entrar'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  awaiting
                      ? (viaWhats ? 'Enviamos um código no WhatsApp para\n$pending' : 'Enviamos um código para\n$pending')
                      : (_signupMode ? 'Comece a atender com IA em minutos' : 'Acesse o painel de atendimento'),
                  style: TextStyle(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (!awaiting && _signupMode) ...[
                  TextField(
                    controller: _company,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome da empresa',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Seu nome',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Seu e-mail',
                      hintText: 'voce@suaempresa.com.br',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Seu WhatsApp (opcional)',
                      hintText: '(21) 99999-9999',
                      prefixIcon: Icon(Icons.smartphone_outlined),
                    ),
                    onSubmitted: (_) => _submitSignup(auth),
                  ),
                ] else if (!awaiting) ...[
                  if (_useEmail)
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      onSubmitted: (_) => _submit(auth),
                    )
                  else
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Celular (WhatsApp)',
                        hintText: '(21) 99999-9999',
                        prefixIcon: Icon(Icons.smartphone_outlined),
                      ),
                      onSubmitted: (_) => _submit(auth),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: auth.busy ? null : () => setState(() => _useEmail = !_useEmail),
                      child: Text(_useEmail ? 'Entrar com celular' : 'Entrar com e-mail'),
                    ),
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
                  onPressed: auth.busy ? null : () => awaiting ? _submitCode(auth) : (_signupMode ? _submitSignup(auth) : _submit(auth)),
                  child: auth.busy
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(awaiting ? 'Confirmar' : (_signupMode ? 'Criar conta' : 'Enviar código')),
                ),
                if (awaiting) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: auth.busy ? null : auth.backToEmail,
                    child: const Text('Voltar'),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: auth.busy ? null : () => setState(() { _signupMode = !_signupMode; _useEmail = false; }),
                    child: Text(_signupMode ? 'Já tenho conta — entrar' : 'Não tem conta? Criar agora'),
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
        const Text('HotZap', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ],
    );
  }

  void _submit(AuthController auth) {
    final id = (_useEmail ? _email.text : _phone.text).trim();
    if (id.isEmpty) return;
    auth.requestCode(id);
  }

  void _submitSignup(AuthController auth) {
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (_company.text.trim().length < 2 || _name.text.trim().length < 2 || (!email.contains('@') && phone.isEmpty)) return;
    auth.signup(_company.text, _name.text, email, phone);
  }

  void _submitCode(AuthController auth) {
    if (_code.text.trim().length < 4) return;
    auth.verifyCode(_code.text);
  }
}
