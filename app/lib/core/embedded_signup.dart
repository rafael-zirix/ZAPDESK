// Embedded Signup da Meta (onboarding via popup). No web usa o SDK JS (interop);
// em outras plataformas, stub.
export 'embedded_result.dart';
export 'embedded_signup_stub.dart' if (dart.library.js_interop) 'embedded_signup_web.dart';
