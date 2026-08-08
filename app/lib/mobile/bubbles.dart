import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/config.dart';
import '../core/url_open.dart';
import '../models/support.dart';
import 'theme_mobile.dart';
import 'widgets.dart';

/// Bolha de mensagem. Recebida à esquerda (branca), enviada à direita (verde) —
/// e a NOTA INTERNA em amarelo, com aviso explícito de que não foi ao cliente.
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.message, this.onRetry});

  final Message message;

  /// Reenvio (só aparece nas que falharam).
  final Future<void> Function()? onRetry;

  bool get _note => message.internal;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final ours = m.isOutbound;
    final bg = _note ? MobileTheme.noteBg : (ours ? MobileTheme.bubbleOut : MobileTheme.bubbleIn);

    return Align(
      alignment: ours ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _menu(context),
        child: Container(
          margin: EdgeInsets.only(
            left: ours ? 52 : 8,
            right: ours ? 8 : 52,
            top: 2,
            bottom: 2,
          ),
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 5),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(9),
              topRight: const Radius.circular(9),
              bottomLeft: Radius.circular(ours ? 9 : 2),
              bottomRight: Radius.circular(ours ? 2 : 9),
            ),
            border: _note ? Border.all(color: MobileTheme.noteBorder) : null,
            boxShadow: _note
                ? null
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 1, offset: const Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_note) _cabecalhoNota(),
              if (m.hasMedia) _midia(context, m),
              if ((m.content ?? '').isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: m.hasMedia ? 6 : 0),
                  child: Text(
                    m.content!,
                    style: TextStyle(fontSize: 15, height: 1.32, color: MobileTheme.text),
                  ),
                ),
              _rodape(context, m),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalhoNota() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          const Icon(Icons.sticky_note_2, size: 13, color: Color(0xFF8A6D00)),
          const SizedBox(width: 4),
          Text(
            message.senderName == null ? 'Nota interna' : 'Nota interna · ${message.senderName}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF8A6D00)),
          ),
        ],
      ),
    );
  }

  Widget _midia(BuildContext context, Message m) {
    final url = Config.apiBaseUrl + m.mediaUrl!;
    if (m.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onTap: () => _verImagem(context, url),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _arquivo(m, url, quebrada: true),
            loadingBuilder: (_, child, prog) => prog == null
                ? child
                : Container(
                    height: 150,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        ),
      );
    }
    if (m.isAudio) return AudioBubble(url: url);
    return _arquivo(m, url);
  }

  /// Cartão de documento (PDF, planilha…). Toca para abrir no app do sistema.
  Widget _arquivo(Message m, String url, {bool quebrada = false}) {
    return InkWell(
      onTap: () => openUrl(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(quebrada ? Icons.broken_image : Icons.insert_drive_file,
                size: 26, color: MobileTheme.brand),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.fileName ?? (quebrada ? 'Imagem indisponível' : 'Documento'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: MobileTheme.text),
                  ),
                  Text('Toque para abrir',
                      style: TextStyle(fontSize: 11, color: MobileTheme.textFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rodape(BuildContext context, Message m) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (m.status == 'failed') ...[
            const Icon(Icons.error_outline, size: 13, color: Color(0xFFB42318)),
            const SizedBox(width: 3),
            GestureDetector(
              onTap: onRetry,
              child: const Text('Falhou — tocar para reenviar',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFB42318), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            DateFormat('HH:mm').format(m.createdAt),
            style: TextStyle(fontSize: 10.5, color: MobileTheme.textFaint),
          ),
          if (m.isOutbound && !_note) ...[
            const SizedBox(width: 3),
            _statusIcone(m.status),
          ],
        ],
      ),
    );
  }

  /// Os "tiquinhos": enviado, entregue e lido — a mesma leitura do WhatsApp.
  Widget _statusIcone(String status) {
    return switch (status) {
      'read' => const Icon(Icons.done_all, size: 14, color: Color(0xFF53BDEB)),
      'delivered' => Icon(Icons.done_all, size: 14, color: MobileTheme.textFaint),
      'sent' => Icon(Icons.done, size: 14, color: MobileTheme.textFaint),
      'failed' => const Icon(Icons.error_outline, size: 14, color: Color(0xFFB42318)),
      _ => Icon(Icons.schedule, size: 12, color: MobileTheme.textFaint),
    };
  }

  Future<void> _menu(BuildContext context) async {
    final texto = message.content ?? '';
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetTitle('Mensagem'),
            if (texto.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copiar texto'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: texto));
                  Navigator.pop(ctx);
                  toast(context, 'Texto copiado');
                },
              ),
            if (message.hasMedia)
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Abrir anexo'),
                onTap: () {
                  Navigator.pop(ctx);
                  openUrl(Config.apiBaseUrl + message.mediaUrl!);
                },
              ),
            if (message.status == 'failed' && onRetry != null)
              ListTile(
                leading: const Icon(Icons.refresh, color: Color(0xFFB42318)),
                title: const Text('Reenviar'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRetry!();
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _verImagem(BuildContext context, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => openUrl(url)),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(url, errorBuilder: (_, _, _) {
                return const Text('Não foi possível carregar a imagem',
                    style: TextStyle(color: Colors.white70));
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// Player de áudio na bolha (o cliente manda muito áudio; sem tocar aqui o
/// atendente teria de sair do app para ouvir).
class AudioBubble extends StatefulWidget {
  const AudioBubble({super.key, required this.url});
  final String url;

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _player = AudioPlayer();
  Duration _total = Duration.zero;
  Duration _pos = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _pos = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    try {
      await _player.play(UrlSource(widget.url));
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) toast(context, 'Não foi possível tocar o áudio', isError: true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progresso = _total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 208,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 34),
            color: MobileTheme.brand,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progresso,
                    minHeight: 4,
                    backgroundColor: MobileTheme.textFaint.withValues(alpha: 0.3),
                    color: MobileTheme.brand,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _total == Duration.zero ? 'Áudio' : '${_fmt(_pos)} / ${_fmt(_total)}',
                  style: TextStyle(fontSize: 10.5, color: MobileTheme.textFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso central de sistema — separador de dia e eventos da conversa
/// ("Fulano assumiu"), no mesmo formato do WhatsApp.
class SystemNote extends StatelessWidget {
  const SystemNote(this.texto, {super.key, this.icone});
  final String texto;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: MobileTheme.systemChip,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[
              Icon(icone, size: 12, color: MobileTheme.systemText),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: MobileTheme.systemText, height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
