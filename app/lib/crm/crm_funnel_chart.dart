import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/crm.dart';
import 'crm_format.dart';

/// Funil ESTILIZADO em pseudo-3D (como o clássico funil de vendas): cada
/// etapa é uma faixa trapezoidal com boca elíptica (anel), sombreamento
/// cilíndrico e base abaulada — nas cores reais das etapas. O afunilamento é
/// visual (fixo); os números são os reais.
class CrmFunnelChart extends StatelessWidget {
  const CrmFunnelChart({super.key, required this.rows});
  final List<CrmFunnelRow> rows;

  static const _funnelWidth = 520.0;
  static const _bandHeight = 62.0;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final n = rows.length;
    final first = rows.first.dealCount;
    // Afunilamento fixo: do topo (100%) até ~30% na última faixa.
    double frac(int i) => 1.0 - (0.68 * i / n);
    return Column(children: [
      for (var i = 0; i < n; i++)
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: _funnelWidth,
            height: _bandHeight,
            child: CustomPaint(
              painter: _Band3D(
                color: hexColor(rows[i].color),
                topFrac: frac(i),
                bottomFrac: frac(i + 1),
                isFirst: i == 0,
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(rows[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              shadows: [Shadow(color: Colors.black38, blurRadius: 4)])),
                    ),
                    if (rows[i].isWon)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Text('🏆', style: TextStyle(fontSize: 13)),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${rows[i].dealCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 170,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(moneyFromCents(rows[i].valueCents),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: hexColor(rows[i].color))),
              if (i > 0 && rows[i - 1].dealCount > 0)
                Text(
                    '${(rows[i].dealCount * 100 / rows[i - 1].dealCount).toStringAsFixed(0)}% da etapa anterior',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
            ]),
          ),
        ]),
      const SizedBox(height: 14),
      // Alvo do funil: a conversão total, centrada sob o bico.
      Padding(
        padding: const EdgeInsets.only(right: 186), // centra sob o funil
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.seed.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.seed.withValues(alpha: .4)),
            ),
            child: Text(
              first == 0
                  ? 'Sem leads no período'
                  : '🎯 Conversão: ${(rows.last.dealCount * 100 / first).toStringAsFixed(1)}%  ·  ${rows.last.dealCount} de $first leads',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, color: AppTheme.seed),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Pinta uma faixa do funil em pseudo-3D: sombra projetada, corpo trapezoidal
/// com degradê cilíndrico (escuro-claro-escuro), base abaulada e a BOCA
/// elíptica no topo (o anel que dá o efeito da foto).
class _Band3D extends CustomPainter {
  const _Band3D({
    required this.color,
    required this.topFrac,
    required this.bottomFrac,
    required this.isFirst,
  });

  final Color color;
  final double topFrac;
  final double bottomFrac;
  final bool isFirst;

  static const _rimH = 16.0; // altura da elipse da boca
  static const _bulge = 7.0; // abaulado da base

  @override
  void paint(Canvas canvas, Size size) {
    final ti = size.width * (1 - topFrac) / 2;
    final bi = size.width * (1 - bottomFrac) / 2;
    final dark = Color.lerp(color, Colors.black, .38)!;
    final mid = color;
    final light = Color.lerp(color, Colors.white, .22)!;
    final rimFill = Color.lerp(color, Colors.white, .34)!;

    // Corpo: trapézio com base abaulada (curva pra baixo).
    final body = Path()
      ..moveTo(ti, _rimH / 2)
      ..lineTo(size.width - ti, _rimH / 2)
      ..lineTo(size.width - bi, size.height - _bulge)
      ..quadraticBezierTo(size.width / 2, size.height + _bulge, bi, size.height - _bulge)
      ..close();

    // Sombra projetada (dá o "descolado da página").
    canvas.drawShadow(body.shift(const Offset(0, 3)), Colors.black.withValues(alpha: .55), 5, false);

    // Degradê cilíndrico: bordas escuras, centro claro — a curvatura do cone.
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [dark, light, mid, light, dark],
      stops: const [0, .28, .5, .72, 1],
    ).createShader(Rect.fromLTWH(ti, 0, size.width - 2 * ti, size.height));
    canvas.drawPath(body, Paint()..shader = shader);

    // Brilho rasante na base abaulada.
    final baseGlow = Path()
      ..moveTo(bi + 4, size.height - _bulge)
      ..quadraticBezierTo(size.width / 2, size.height + _bulge, size.width - bi - 4, size.height - _bulge)
      ..quadraticBezierTo(size.width / 2, size.height + _bulge - 4, bi + 4, size.height - _bulge);
    canvas.drawPath(baseGlow, Paint()..color = Colors.black.withValues(alpha: .18));

    // A BOCA: elipse no topo (anel 3D). Na primeira faixa ela é mais alta —
    // a abertura do funil; nas demais, o anel de encaixe.
    final rimRect = Rect.fromLTWH(ti, 0, size.width - 2 * ti, _rimH);
    canvas.drawOval(rimRect, Paint()..color = rimFill);
    // Sombreamento interno da boca (côncavo).
    final innerRect = Rect.fromLTWH(ti + 6, 2.5, size.width - 2 * ti - 12, _rimH - 5);
    canvas.drawOval(
        innerRect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(color, Colors.black, .30)!, Color.lerp(color, Colors.white, .10)!],
          ).createShader(innerRect));
    // Contorno fino do anel.
    canvas.drawOval(
        rimRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = dark.withValues(alpha: .55));
  }

  @override
  bool shouldRepaint(_Band3D old) =>
      old.color != color || old.topFrac != topFrac || old.bottomFrac != bottomFrac;
}
