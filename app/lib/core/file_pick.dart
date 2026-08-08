// Seletor de arquivo multiplataforma. No web usa um <input type=file> nativo
// (evita o bug do file_picker v11); no celular, file_selector + image_picker.
// As duas implementações expõem pickFile() e pickImage() com a mesma assinatura,
// então a tela de conversa é a mesma no painel e no app.
export 'picked_file.dart';
export 'file_pick_io.dart' if (dart.library.js_interop) 'file_pick_web.dart';
