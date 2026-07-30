// Seletor de arquivo multiplataforma. No web usa um <input type=file> nativo
// (evita o bug do file_picker v11); em mobile, stub por enquanto.
export 'picked_file.dart';
export 'file_pick_stub.dart' if (dart.library.js_interop) 'file_pick_web.dart';
