import 'package:flutter/material.dart';

/// Logo da IA: um badge com a cor da marca e um ícone do Material.
///
/// Ícone do Material em vez de SVG externo — o projeto não tem flutter_svg e a
/// CSP do painel bloqueia imagem de fora. Reconhecível pela cor; dá para trocar
/// pelos SVGs exatos depois, se valer a dependência. Compartilhado entre a folha
/// de troca de IA (cliente) e a tabela de custos (super-admin).
Widget aiLogo(String slug, {double size = 34}) {
  late final Color bg;
  late final IconData ic;
  switch (slug) {
    case 'claude':
      bg = const Color(0xFFD97757); // clay da Anthropic
      ic = Icons.brightness_7; // sol/raios ≈ o mark da Anthropic
      break;
    case 'gpt':
      bg = const Color(0xFF10A37F); // verde OpenAI
      ic = Icons.hub;
      break;
    case 'deepseek':
      bg = const Color(0xFF4D6BFE); // azul DeepSeek
      ic = Icons.waves; // baleia/oceano
      break;
    case 'gemini':
      bg = const Color(0xFF4285F4); // azul Google
      ic = Icons.auto_awesome; // a "faísca" do Gemini
      break;
    default:
      // Sem logo definido: um marcador neutro.
      bg = const Color(0xFF9AA5B1);
      ic = Icons.smart_toy_outlined;
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .28)),
    child: Icon(ic, color: Colors.white, size: size * .56),
  );
}
