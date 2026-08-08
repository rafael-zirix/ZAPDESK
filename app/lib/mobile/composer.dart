import 'package:flutter/material.dart';

import '../inbox/conversation_controller.dart';
import '../inbox/inbox_controller.dart';
import 'sheets.dart';
import 'theme_mobile.dart';
import 'widgets.dart';

/// Barra de envio. Em modo normal: anexo, campo, mensagens prontas, rascunho da
/// IA e o botão que alterna entre microfone (segurar para gravar) e enviar.
/// Em modo NOTA INTERNA a barra fica amarela — o atendente não pode ter dúvida
/// de que aquilo não vai para o cliente.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.conv, required this.inbox, this.onSent});

  final ConversationController conv;
  final InboxController inbox;
  final VoidCallback? onSent;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  /// Passou do limite arrastando para a esquerda → cancela a gravação.
  bool _vaiCancelar = false;

  ConversationController get _conv => widget.conv;

  @override
  Widget build(BuildContext context) {
    if (_conv.recording) return _gravando();

    final nota = _conv.noteMode;
    // Conversa de outro atendente: só a NOTA INTERNA continua liberada (ela não
    // chega ao cliente). A mesma regra roda no servidor — aqui é para a tela não
    // oferecer o que vai voltar 403.
    final travado = _conv.lockedByOther && !nota;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_conv.lockedByOther) _avisoTravado(),
          if (nota) _avisoNota(),
          if (_conv.replyTo != null) _avisoResposta(),
          if (_conv.pendingTemplate != null) _avisoModelo(),
          Container(
            color: nota ? MobileTheme.noteBg : MobileTheme.composerBg,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Anexar',
                  icon: const Icon(Icons.add_circle_outline),
                  color: MobileTheme.textFaint,
                  onPressed: travado ? null : () => attachSheet(context, _conv, widget.inbox),
                ),
                Expanded(child: _campo(nota, travado)),
                const SizedBox(width: 4),
                _botaoDireita(nota, travado),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Faixa que explica por que o campo está travado e o que fazer a respeito.
  Widget _avisoTravado() {
    final quem = _conv.lockedByName ?? 'outro atendente';
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFF4CC),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: Color(0xFF8A6D00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _conv.noteMode
                  ? 'Em atendimento com $quem — sua nota interna não vai ao cliente.'
                  : 'Em atendimento com $quem. Peça a transferência para responder.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A6D00), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  /// Prévia "respondendo a…" — o mesmo desenho da faixa de nota, com o X.
  Widget _avisoResposta() {
    final m = _conv.replyTo!;
    final autor = m.isOutbound ? (m.senderName ?? 'Você') : 'Cliente';
    return Container(
      width: double.infinity,
      color: MobileTheme.composerBg,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 0),
      child: Row(
        children: [
          Container(width: 3.5, height: 34, color: MobileTheme.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Respondendo a $autor',
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: MobileTheme.brand)),
                Text(
                  m.shortPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: MobileTheme.textFaint),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: MobileTheme.textFaint,
            visualDensity: VisualDensity.compact,
            onPressed: () {
              _conv.clearReply();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _campo(bool nota, bool travado) {
    return Container(
      decoration: BoxDecoration(
        color: nota ? Colors.white.withValues(alpha: 0.55) : MobileTheme.composerField,
        borderRadius: BorderRadius.circular(22),
        border: nota ? Border.all(color: MobileTheme.noteBorder) : null,
      ),
      padding: const EdgeInsets.only(left: 14, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _conv.composer,
              enabled: !travado,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              style: TextStyle(fontSize: 15.5, color: MobileTheme.text),
              onChanged: (_) => setState(() {}), // alterna mic ↔ enviar
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: travado
                    ? 'Conversa de outro atendente'
                    : nota
                        ? 'Nota interna (só a equipe vê)'
                        : 'Mensagem',
                hintStyle: TextStyle(color: MobileTheme.textFaint, fontSize: 15),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          if (!nota && !travado) ...[
            IconButton(
              tooltip: 'Mensagens prontas',
              icon: const Icon(Icons.bolt, size: 22),
              color: MobileTheme.textFaint,
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await quickRepliesSheet(context, _conv, widget.inbox);
                if (mounted) setState(() {});
              },
            ),
            // Rascunho da IA: escreve no campo para o atendente revisar; nada é
            // enviado sozinho.
            if (widget.inbox.aiEnabled)
              IconButton(
                tooltip: 'Rascunho da IA',
                icon: _conv.suggesting
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 20),
                color: MobileTheme.brand,
                visualDensity: VisualDensity.compact,
                onPressed: _conv.suggesting ? null : _sugerir,
              ),
          ],
        ],
      ),
    );
  }

  /// Direita: enviar quando há texto; microfone quando não há. Nota interna
  /// nunca vira áudio (nota é sempre texto).
  Widget _botaoDireita(bool nota, bool travado) {
    final temTexto = _conv.composer.text.trim().isNotEmpty;
    final enviando = _conv.sending;

    // Travado: cadeado inerte no lugar do microfone, para não parecer que o
    // atendente pode gravar um áudio que nunca sairia.
    if (travado) {
      return _Redondo(cor: MobileTheme.textFaint, icone: Icons.lock_outline, onTap: null);
    }

    if (temTexto || nota) {
      return _Redondo(
        cor: nota ? const Color(0xFFCC9A06) : MobileTheme.brand,
        icone: nota ? Icons.sticky_note_2 : Icons.send,
        onTap: enviando || !temTexto ? null : _enviar,
        carregando: enviando,
      );
    }

    // Push-to-talk: segurar grava, soltar envia, arrastar para a esquerda cancela.
    return GestureDetector(
      onLongPressStart: (_) => _iniciarGravacao(),
      onLongPressMoveUpdate: (d) {
        final cancelar = d.localOffsetFromOrigin.dx < -70;
        if (cancelar != _vaiCancelar) setState(() => _vaiCancelar = cancelar);
      },
      onLongPressEnd: (_) => _terminarGravacao(),
      onTap: () => toast(context, 'Segure o microfone para gravar'),
      child: _Redondo(cor: MobileTheme.brand, icone: Icons.mic, onTap: null),
    );
  }

  Widget _gravando() {
    final s = _conv.recordSeconds;
    final tempo = '${(s ~/ 60)}:${(s % 60).toString().padLeft(2, '0')}';
    return SafeArea(
      top: false,
      child: Container(
        color: MobileTheme.composerBg,
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 14),
        child: Row(
          children: [
            const _PontoVermelho(),
            const SizedBox(width: 10),
            Text(tempo,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: MobileTheme.text, fontFeatures: null)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                _vaiCancelar ? 'Solte para CANCELAR' : 'Solte para enviar · arraste ← para cancelar',
                style: TextStyle(
                  fontSize: 12.5,
                  color: _vaiCancelar ? const Color(0xFFB42318) : MobileTheme.textFaint,
                  fontWeight: _vaiCancelar ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Icon(Icons.mic, color: _vaiCancelar ? const Color(0xFFB42318) : MobileTheme.brand, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _avisoNota() {
    return Container(
      width: double.infinity,
      color: MobileTheme.noteBorder.withValues(alpha: 0.45),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          const Icon(Icons.visibility_off, size: 15, color: Color(0xFF8A6D00)),
          const SizedBox(width: 7),
          const Expanded(
            child: Text('Nota interna — o cliente NÃO recebe',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A6D00))),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 17),
            color: const Color(0xFF8A6D00),
            visualDensity: VisualDensity.compact,
            onPressed: () {
              _conv.toggleNoteMode();
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _avisoModelo() {
    final t = _conv.pendingTemplate!;
    return Container(
      width: double.infinity,
      color: const Color(0xFFE7F8EE),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          const Icon(Icons.verified, size: 15, color: Color(0xFF157347)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Modelo "${t.name}" pronto — enviar assim fura a janela de 24h. Editar o texto o transforma em mensagem comum.',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF157347), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // --- Ações ---

  Future<void> _enviar() async {
    final nota = _conv.noteMode;
    final ok = nota ? await _conv.sendNote() : await _conv.send();
    if (!mounted) return;
    setState(() {});
    if (!ok) {
      // A conversa pode ter sido assumida por outro no meio da digitação: nesse
      // caso o controller devolve o texto ao campo e traz o motivo do servidor.
      final motivo = _conv.lastError;
      toast(
        context,
        motivo ?? (nota ? 'Não foi possível gravar a nota' : 'A mensagem não saiu'),
        isError: true,
      );
      _conv.lastError = null;
      return;
    }
    widget.onSent?.call();
  }

  Future<void> _sugerir() async {
    final erro = await _conv.suggestReply();
    if (!mounted) return;
    setState(() {});
    if (erro != null) toast(context, erro, isError: true);
  }

  Future<void> _iniciarGravacao() async {
    final ok = await _conv.startRecording();
    if (!mounted) return;
    if (!ok) {
      toast(context, 'Sem acesso ao microfone. Libere a permissão nas configurações.', isError: true);
      return;
    }
    setState(() => _vaiCancelar = false);
  }

  Future<void> _terminarGravacao() async {
    if (!_conv.recording) return;
    if (_vaiCancelar) {
      _conv.cancelRecording();
      if (mounted) setState(() => _vaiCancelar = false);
      return;
    }
    // Toque rápido demais: não vale mandar um áudio de menos de 1 segundo.
    if (_conv.recordSeconds < 1) {
      _conv.cancelRecording();
      if (mounted) {
        setState(() {});
        toast(context, 'Gravação muito curta');
      }
      return;
    }
    final ok = await _conv.stopAndSendRecording();
    if (!mounted) return;
    setState(() {});
    if (!ok) {
      toast(context, 'Não foi possível enviar o áudio', isError: true);
      return;
    }
    widget.onSent?.call();
  }
}

/// Botão redondo do canto direito (enviar / microfone).
class _Redondo extends StatelessWidget {
  const _Redondo({required this.cor, required this.icone, this.onTap, this.carregando = false});
  final Color cor;
  final IconData icone;
  final VoidCallback? onTap;
  final bool carregando;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
      child: carregando
          ? const Padding(
              padding: EdgeInsets.all(13),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : IconButton(
              onPressed: onTap,
              icon: Icon(icone, color: Colors.white, size: 21),
              // Sem onTap (microfone) o IconButton ficaria acinzentado; o gesto de
              // segurar é tratado pelo GestureDetector de fora.
              disabledColor: Colors.white,
            ),
    );
  }
}

/// Bolinha vermelha piscando durante a gravação.
class _PontoVermelho extends StatefulWidget {
  const _PontoVermelho();

  @override
  State<_PontoVermelho> createState() => _PontoVermelhoState();
}

class _PontoVermelhoState extends State<_PontoVermelho> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c.drive(Tween(begin: 0.35, end: 1)),
      child: Container(
        width: 11,
        height: 11,
        decoration: const BoxDecoration(color: Color(0xFFE53935), shape: BoxShape.circle),
      ),
    );
  }
}
