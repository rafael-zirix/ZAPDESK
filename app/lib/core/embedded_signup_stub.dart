import 'embedded_result.dart';

/// Fora do web, o Embedded Signup não está disponível.
Future<EmbeddedResult?> runEmbeddedSignup({
  required String appId,
  required String configId,
  required String graphVersion,
}) async =>
    null;

/// Fora do web, o login da Meta não está disponível.
Future<(String, String)?> runFacebookLogin({
  required String appId,
  required String configId,
  required String graphVersion,
}) async =>
    null;
