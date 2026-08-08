import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/api_client.dart';

/// Notificações no celular (FCM).
///
/// É TOLERANTE A NÃO ESTAR CONFIGURADO: sem o google-services.json do projeto
/// Firebase, o `initializeApp` falha, [disponivel] fica false e o app segue
/// funcionando com o polling — só não avisa com a tela apagada. Assim o APK
/// compila e roda antes de existir projeto Firebase.
class Push {
  Push._();
  static final Push instance = Push._();

  static const _canal = AndroidNotificationChannel(
    'mensagens',
    'Mensagens',
    description: 'Avisos de mensagens novas dos clientes',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();

  bool disponivel = false;
  String? _token;

  /// Conversa que o atendente quis abrir ao tocar na notificação. A lista de
  /// conversas escuta isto e navega — evita um navigatorKey global.
  final abrirTicket = ValueNotifier<String?>(null);

  /// Liga tudo: permissão, canal, token e escutas. Chamado após o login.
  Future<void> iniciar() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('push: Firebase não configurado ($e) — seguindo sem notificações');
      disponivel = false;
      return;
    }
    try {
      final fm = FirebaseMessaging.instance;
      final perm = await fm.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('push: permissão negada pelo usuário');
        return;
      }

      await _local.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null && r.payload!.isNotEmpty) abrirTicket.value = r.payload;
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_canal);

      // Com o app aberto o FCM não mostra nada sozinho: exibimos a notificação.
      FirebaseMessaging.onMessage.listen(_mostrar);
      // Toque na notificação com o app em segundo plano.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final id = m.data['ticket_id'];
        if (id is String && id.isNotEmpty) abrirTicket.value = id;
      });
      // App aberto a partir de uma notificação com o processo morto.
      final inicial = await fm.getInitialMessage();
      final idInicial = inicial?.data['ticket_id'];
      if (idInicial is String && idInicial.isNotEmpty) abrirTicket.value = idInicial;

      fm.onTokenRefresh.listen(_registrar);
      final token = await fm.getToken();
      if (token != null) await _registrar(token);

      disponivel = true;
    } catch (e) {
      debugPrint('push: falha ao iniciar ($e)');
      disponivel = false;
    }
  }

  Future<void> _mostrar(RemoteMessage m) async {
    final n = m.notification;
    final titulo = n?.title ?? m.data['title'] as String? ?? 'Nova mensagem';
    final corpo = n?.body ?? m.data['body'] as String? ?? '';
    await _local.show(
      // Uma notificação por conversa: a nova substitui a anterior em vez de
      // empilhar 20 avisos do mesmo cliente.
      id: (m.data['ticket_id'] as String? ?? titulo).hashCode & 0x7fffffff,
      title: titulo,
      body: corpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _canal.id,
          _canal.name,
          channelDescription: _canal.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: m.data['ticket_id'] as String?,
    );
  }

  Future<void> _registrar(String token) async {
    _token = token;
    await ApiClient.instance.post('/devices', {
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    });
  }

  /// Descadastra o aparelho (chamado no logout) — senão o atendente continuaria
  /// recebendo mensagens da empresa depois de sair.
  Future<void> desligar() async {
    final t = _token;
    _token = null;
    if (t == null) return;
    await ApiClient.instance.delete('/devices/$t');
  }
}
