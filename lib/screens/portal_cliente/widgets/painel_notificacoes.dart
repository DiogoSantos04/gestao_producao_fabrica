import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/notificacao_model.dart';

/// Sino com o número de avisos por ler, para o cabeçalho da barra lateral.
///
/// O contador é o que dá sentido a guardar as notificações: até aqui um aviso
/// vivia oito segundos num SnackBar e desaparecia para sempre, mesmo que
/// ninguém estivesse a olhar para o ecrã.
class SinoNotificacoes extends StatelessWidget {
  const SinoNotificacoes({
    super.key,
    required this.porLer,
    required this.onPressed,
    this.corIcone = TemasCores.textoInversoClaro,
  });

  final int porLer;
  final VoidCallback onPressed;
  final Color corIcone;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: porLer == 0 ? 'Notificações' : '$porLer por ler',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          // O emblema sai fora do quadrado do ícone de propósito; `clipBehavior`
          // impede que o `Stack` o corte.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                porLer > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                color: corIcone,
                size: 22,
              ),
              if (porLer > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 17),
                    decoration: BoxDecoration(
                      color: TemasCores.erro,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: TemasCores.marcaEscura, width: 1.5),
                    ),
                    child: Text(
                      // Acima de 9 o emblema deixaria de caber sem empurrar o
                      // ícone; o número exato não acrescenta nada aqui.
                      porLer > 9 ? '9+' : '$porLer',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TemasCores.textoInverso,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Abre a lista de notificações.
///
/// Em ecrã largo aparece encostada ao sino, como um painel suspenso; em ecrã
/// estreito sobe de baixo, que é onde o polegar chega. É o mesmo conteúdo nos
/// dois casos — só muda por onde entra.
Future<void> mostrarPainelNotificacoes(
  BuildContext context, {
  required List<NotificacaoModel> notificacoes,
  required bool ancorarAoSino,
  required void Function(NotificacaoModel) aoAbrirEncomenda,
  required Future<void> Function() aoMarcarTodasLidas,
}) {
  final lista = _ListaNotificacoes(
    notificacoes: notificacoes,
    aoAbrirEncomenda: aoAbrirEncomenda,
    aoMarcarTodasLidas: aoMarcarTodasLidas,
  );

  if (!ancorarAoSino) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: TemasCores.superficie,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: lista,
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.08),
    builder: (_) => Padding(
      // Encosta ao sino: 260 é a largura da barra lateral do portal.
      padding: const EdgeInsets.only(left: 268, top: 64),
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: TemasCores.superficie,
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 460),
            child: lista,
          ),
        ),
      ),
    ),
  );
}

class _ListaNotificacoes extends StatelessWidget {
  const _ListaNotificacoes({
    required this.notificacoes,
    required this.aoAbrirEncomenda,
    required this.aoMarcarTodasLidas,
  });

  final List<NotificacaoModel> notificacoes;
  final void Function(NotificacaoModel) aoAbrirEncomenda;
  final Future<void> Function() aoMarcarTodasLidas;

  @override
  Widget build(BuildContext context) {
    final porLer = notificacoes.where((n) => !n.lida).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Notificações',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoPrimario,
                  ),
                ),
              ),
              if (porLer > 0)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    aoMarcarTodasLidas();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: TemasCores.clienteAcento,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Marcar todas como lidas', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (notificacoes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 44, horizontal: 24),
            child: Column(
              children: [
                Icon(Icons.notifications_none_rounded, size: 34, color: TemasCores.textoApoio),
                SizedBox(height: 10),
                Text(
                  'Ainda não tem notificações.',
                  style: TextStyle(fontSize: 13, color: TemasCores.textoApoio),
                ),
                SizedBox(height: 4),
                Text(
                  'Avisamos aqui quando as suas encomendas mudarem de estado.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: TemasCores.textoApoio),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: notificacoes.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
              itemBuilder: (_, i) => _LinhaNotificacao(
                notificacao: notificacoes[i],
                aoAbrirEncomenda: aoAbrirEncomenda,
              ),
            ),
          ),
      ],
    );
  }
}

class _LinhaNotificacao extends StatelessWidget {
  const _LinhaNotificacao({required this.notificacao, required this.aoAbrirEncomenda});

  final NotificacaoModel notificacao;
  final void Function(NotificacaoModel) aoAbrirEncomenda;

  @override
  Widget build(BuildContext context) {
    // Só há para onde ir quando o aviso diz respeito a uma encomenda concreta.
    final bool navegavel = notificacao.codigoRastreio != null;

    return InkWell(
      onTap: navegavel
          ? () {
              Navigator.of(context).pop();
              aoAbrirEncomenda(notificacao);
            }
          : null,
      child: Container(
        // O fundo tingido é o que distingue por ler de lida sem precisar de
        // legenda.
        color: notificacao.lida ? null : TemasCores.clienteAcento.withValues(alpha: 0.06),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(notificacao.evento.icone, color: notificacao.evento.cor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notificacao.titulo,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: TemasCores.textoPrimario,
                            fontWeight: notificacao.lida ? FontWeight.w500 : FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        notificacao.quandoRelativo,
                        style: const TextStyle(fontSize: 11, color: TemasCores.textoApoio),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notificacao.mensagem,
                    style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio, height: 1.35),
                  ),
                  if (navegavel) ...[
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Text(
                          'Ver rastreio',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: TemasCores.clienteAcento,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            size: 15, color: TemasCores.clienteAcento),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
