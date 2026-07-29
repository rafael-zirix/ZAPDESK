/// Configuração do app. A URL da API pode ser injetada no build com
/// --dart-define=API_BASE_URL=... ; em dev cai no backend local (porta 8082).
class Config {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8082',
  );

  static const appName = 'Zapdesk';
}
