import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import 'cartao_painel.dart';

/// Acima deste total de minutos a encomenda conta como carga elevada (8 horas).
const int _limiteCargaElevadaMinutos = 480;

/// Pré-visualização das fases por que a encomenda vai passar, com o lead time
/// estimado e a fase mais demorada da linha.
class PainelPreviewFluxo extends StatefulWidget {
  const PainelPreviewFluxo({
    super.key,
    required this.fases,
    required this.quantidade,
    required this.aCarregar,
    required this.eDesktop,
  });

  /// Fases do fluxo do tipo de produto escolhido, por ordem.
  final List<Map<String, dynamic>> fases;

  /// Quantidade a produzir; multiplica o tempo unitário.
  final int quantidade;

  final bool aCarregar;
  final bool eDesktop;

  @override
  State<PainelPreviewFluxo> createState() => _PainelPreviewFluxoState();
}

class _PainelPreviewFluxoState extends State<PainelPreviewFluxo> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(PainelPreviewFluxo oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fluxo novo começa a ser lido de cima.
    if (!identical(oldWidget.fases, widget.fases) && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _tempoUnitarioMinutos => widget.fases
      .fold<int>(0, (total, f) => total + (f['tempo_estimado'] as num? ?? 0).toInt());

  int get _tempoTotalMinutos =>
      _tempoUnitarioMinutos * (widget.quantidade > 0 ? widget.quantidade : 1);

  /// Fase com maior tempo de ciclo: é ela que dita o ritmo da linha.
  Map<String, dynamic>? get _faseMaisDemorada {
    if (widget.fases.isEmpty) return null;
    return widget.fases.reduce((a, b) =>
        (b['tempo_estimado'] as num? ?? 0) > (a['tempo_estimado'] as num? ?? 0) ? b : a);
  }

  @override
  Widget build(BuildContext context) {
    final Widget conteudo;

    if (widget.aCarregar) {
      conteudo = const Center(child: CircularProgressIndicator());
    } else if (widget.fases.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Selecione um tipo de produto para ver o fluxo',
          style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
        ),
      );
    } else {
      final int tempoTotal = _tempoTotalMinutos;

      conteudo = Column(
        children: [
          CartaoLeadTime(
            tempoTotalMinutos: tempoTotal,
            tempoUnitarioMinutos: _tempoUnitarioMinutos,
            faseMaisDemorada: _faseMaisDemorada,
            eCargaElevada: tempoTotal > _limiteCargaElevadaMinutos,
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: widget.fases.length,
                padding: const EdgeInsets.only(right: 12),
                itemBuilder: (context, idx) => _LinhaFase(fase: widget.fases[idx]),
              ),
            ),
          ),
        ],
      );
    }

    return CartaoPainel(
      titulo: 'Pré-visualização do Fluxo',
      subtitulo: 'Fases que a encomenda irá seguir automaticamente',
      expandirConteudo: widget.eDesktop,
      alturaConteudo: 320,
      conteudo: conteudo,
    );
  }
}

/// Formata minutos como `2h 30m`.
String formatarTempo(int minutos) {
  if (minutos <= 0) return '0 min';
  final int horas = minutos ~/ 60;
  final int minsRestantes = minutos % 60;

  if (horas == 0) return '${minsRestantes}m';
  if (minsRestantes == 0) return '${horas}h';
  return '${horas}h ${minsRestantes}m';
}

/// Cartão com a carga total estimada, a fase mais demorada e o alerta de carga
/// elevada.
class CartaoLeadTime extends StatelessWidget {
  const CartaoLeadTime({
    super.key,
    required this.tempoTotalMinutos,
    required this.tempoUnitarioMinutos,
    required this.faseMaisDemorada,
    required this.eCargaElevada,
  });

  final int tempoTotalMinutos;
  final int tempoUnitarioMinutos;
  final Map<String, dynamic>? faseMaisDemorada;
  final bool eCargaElevada;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemasCores.resumoFundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.resumoBorda),
      ),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: 18, color: TemasCores.resumoTexto),
                  SizedBox(width: 8),
                  Text(
                    'Carga Total Estimada:',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.resumoTexto),
                  ),
                ],
              ),
              Text(
                '${formatarTempo(tempoTotalMinutos)} (${formatarTempo(tempoUnitarioMinutos)}/unid)',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.resumoTextoForte),
              ),
            ],
          ),
          if (faseMaisDemorada != null) ...[
            const Divider(height: 14),
            Row(
              children: [
                const Icon(Icons.hourglass_bottom_rounded,
                    size: 15, color: TemasCores.avisoTextoForte),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Fase mais demorada: ${faseMaisDemorada!['nome_fase_padrao']} '
                    '(${faseMaisDemorada!['tempo_estimado']} min no '
                    '${faseMaisDemorada!['posto_trabalho'] ?? 'Posto'})',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TemasCores.avisoTextoForte),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (eCargaElevada) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: TemasCores.alertaFundoForte, borderRadius: BorderRadius.circular(4)),
              child: const Text(
                '⚡ Esta encomenda representa uma carga de fabrico elevada (+8 horas).',
                style: TextStyle(
                    fontSize: 10,
                    color: TemasCores.alertaTextoForte,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Uma fase do fluxo: ordem, nome, posto e tempo estimado.
class _LinhaFase extends StatelessWidget {
  const _LinhaFase({required this.fase});

  final Map<String, dynamic> fase;

  @override
  Widget build(BuildContext context) {
    final posto = fase['posto_trabalho']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: TemasCores.superficieEscura, borderRadius: BorderRadius.circular(6)),
            child: Text(
              '${fase['ordem']}',
              style: const TextStyle(
                  color: TemasCores.textoInverso, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fase['nome_fase_padrao'] ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (posto.isNotEmpty)
                  Text(
                    'Posto: $posto',
                    style: const TextStyle(color: TemasCores.textoApoio, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '⏱️ ${fase['tempo_estimado']} min',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.textoApoio),
          ),
        ],
      ),
    );
  }
}
