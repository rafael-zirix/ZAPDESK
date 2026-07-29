import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'admin/accounts_controller.dart';
import 'auth/auth_controller.dart';
import 'auth/login_screen.dart';
import 'contacts/contacts_controller.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'inbox/inbox_controller.dart';
import 'shell/app_shell.dart';
import 'users/users_controller.dart';
import 'whatsapp/whatsapp_controller.dart';

void main() {
  runApp(const ZapdeskApp());
}

class ZapdeskApp extends StatelessWidget {
  const ZapdeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()..bootstrap()),
        ChangeNotifierProvider(create: (_) => InboxController()),
        ChangeNotifierProvider(create: (_) => ContactsController()),
        ChangeNotifierProvider(create: (_) => AccountsController()),
        ChangeNotifierProvider(create: (_) => UsersController()),
        ChangeNotifierProvider(create: (_) => WhatsAppController()),
      ],
      child: MaterialApp(
        title: Config.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return switch (auth.status) {
      AuthStatus.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.loggedIn => const AppShell(),
      _ => const LoginScreen(),
    };
  }
}
