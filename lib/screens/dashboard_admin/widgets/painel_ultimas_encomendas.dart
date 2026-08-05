import 'package:flutter/material.dart';

import '../../../core/formatos.dart';
import '../../../core/temas_cores.dart';
import '../../../models/encomenda_model.dart';
import 'cartao_painel.dart';

/// Lista das ordens lançadas mais recentemente, para confirmar num relance que
/// o lançamento entrou.
class PainelUltimasEncomendas extends StatefulWidget {
  const PainelUltimasEncomendas({
    super.key,
    required this.encomendas,
    required this.eDesktop,
  });

  final List<EncomendaModel> encomendas;
  final bool eDesktop;

  @override
  State<PainelUltimasEncomendas> createState() => _PainelUltimasEncomendasState();
}

class _PainelUltimasEncomendasState extends State<PainelUltimasEncomendas> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget conteudo;

    if (widget.encomendas.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Nenhuma encomenda registada recentemente.',
          style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _scrollController,
          itemCount: widget.encomendas.length,
          padding: const EdgeInsets.only(right: 12),
          itemBuilder: (context, index) =>
              _CartaoUltimaEncomenda(encomenda: widget.encomendas[index]),
        ),
      );
    }

    return CartaoPainel(
      titulo: 'Últimas Encomendas Lançadas',
      expandirConteudo: widget.eDesktop,
      alturaConteudo: 400,
      conteudo: conteudo,
    );
  }
}

/// Cartão de uma das últimas ordens lançadas.
class _CartaoUltimaEncomenda extends StatelessWidget {
  const _CartaoUltimaEncomenda({required this.encomenda});

  final EncomendaModel encomenda;

  /// Cores do badge de prioridade. `Normal` não mostra badge.
  static ({Color texto, Color fundo}) _coresPrioridade(String prioridade) {
    return switch (prioridade) {
      'Urgente' => (texto: TemasCores.alertaTextoForte, fundo: TemasCores.alertaFundo),
      'Crítica' => (texto: TemasCores.erroTextoIntenso, fundo: TemasCores.erroFundo),
      _ => (texto: TemasCores.textoApoioForte, fundo: TemasCores.superficieSuave),
    };
  }

  @override
  Widget build(BuildContext context) {
    final referencia = Formatos.referenciaOrdem(
      encomenda.id,
      criadaEm: encomenda.createdAt?.toIso8601String(),
    );
    final cores = _coresPrioridade(encomenda.prioridade);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      referencia,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: TemasCores.textoPrimario),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: TemasCores.superficieSuave,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        encomenda.codigoRastreio ?? '',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: TemasCores.textoApoioForte),
                      ),
                    ),
                    if (encomenda.prioridade != 'Normal')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: cores.fundo, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          encomenda.prioridade.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold, color: cores.texto),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(encomenda.nomeCliente ?? 'Desconhecido',
                    style: const TextStyle(color: TemasCores.textoApoioForte, fontSize: 12)),
                Text(encomenda.nomeProduto ?? 'N/A',
                    style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                encomenda.dataEntregaIso ?? '',
                style: const TextStyle(
                    fontSize: 11,
                    color: TemasCores.textoDesativado,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: TemasCores.infoFundo, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Qtd: ${encomenda.quantidade}',
                  style: const TextStyle(
                      fontSize: 10, color: TemasCores.infoTexto, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
