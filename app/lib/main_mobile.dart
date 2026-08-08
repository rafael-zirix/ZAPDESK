import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'auth/auth_controller.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'inbox/inbox_controller.dart';
import 'mobile/chats_screen.dart';
import 'mobile/login_mobile.dart';
import 'mobile/push.dart';
import 'mobile/theme_mobile.dart';

/// Entrypoint do app de celular (Android/iOS):
///   flutter run -t lib/main_mobile.dart
///   flutter build apk --release -t lib/main_mobile.dart --dart-define=API_BASE_URL=https://hotzap.com.br
///
/// O painel web continua em lib/main.dart — os dois compartilham api_client,
/// models e os controllers do inbox, então uma correção de regra vale para os dois.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Datas em português ("Ontem", "5 de agosto", "seg") — sem isto o DateFormat
  // com locale pt_BR lança em tempo de execução.
  initializeDateFormatting('pt_BR');
  Intl.defaultLocale = 'pt_BR';
  runApp(const HotZapMobile());
}

class HotZapMobile extends StatelessWidget {
  const HotZapMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthController()..bootstrap()),
        ChangeNotifierProvider(create: (_) => InboxController()),
        ChangeNotifierProvider(create: (_) => MobileThemeController()),
      ],
      child: Consumer<MobileThemeController>(
        builder: (context, theme, _) {
          AppTheme.isDark = theme.isDark; // sincroniza antes de construir a árvore
          return MaterialApp(
            title: Config.appName,
            debugShowCheckedModeBanner: false,
            theme: MobileTheme.build(Brightness.light),
            darkTheme: MobileTheme.build(Brightness.dark),
            themeMode: theme.mode,
            home: const _Root(),
          );
        },
      ),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _pushLigado = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    // Registra o aparelho para notificações depois de entrar (uma vez por
    // sessão). Fica aqui, e não na tela de conversas, porque o token precisa ir
    // ao servidor mesmo que o atendente nunca abra uma conversa.
    if (auth.status == AuthStatus.loggedIn && !_pushLigado) {
      _pushLigado = true;
      Push.instance.iniciar();
    }
    if (auth.status == AuthStatus.loggedOut) _pushLigado = false;

    return switch (auth.status) {
      AuthStatus.loading => Scaffold(
          backgroundColor: MobileTheme.appBar,
          body: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      AuthStatus.loggedIn => const ChatsScreen(),
      _ => const LoginMobile(),
    };
  }
}
