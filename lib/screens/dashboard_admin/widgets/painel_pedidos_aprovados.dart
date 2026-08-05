import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/pedido_model.dart';

/// Faixa horizontal com os pedidos da App já aprovados que aguardam agendamento.
///
/// Clicar num cartão preenche o formulário de lançamento com os dados do pedido.
class PainelPedidosAprovados extends StatefulWidget {
  const PainelPedidosAprovados({
    super.key,
    required this.pedidos,
    required this.pedidoSelecionadoId,
    required this.aoSelecionar,
  });

  final List<PedidoModel> pedidos;
  final int? pedidoSelecionadoId;
  final ValueChanged<PedidoModel> aoSelecionar;

  @override
  State<PainelPedidosAprovados> createState() => _PainelPedidosAprovadosState();
}

class _PainelPedidosAprovadosState extends State<PainelPedidosAprovados> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: TemasCores.infoFundo.withValues(alpha: 0.6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.infoBorda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.move_to_inbox_rounded, color: TemasCores.infoTextoForte, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Pedidos Aprovados (App)',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.infoTextoIntenso),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: TemasCores.infoTexto, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${widget.pedidos.length} pendentes',
                    style: const TextStyle(
                        color: TemasCores.textoInverso, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Clique num pedido para preencher automaticamente o formulário de agendamento',
              style: TextStyle(fontSize: 12, color: TemasCores.infoTextoForte),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.pedidos.length,
                  itemBuilder: (context, idx) {
                    final pedido = widget.pedidos[idx];
                    return _CartaoPedidoAprovado(
                      pedido: pedido,
                      selecionado: widget.pedidoSelecionadoId == pedido.id,
                      aoTocar: () => widget.aoSelecionar(pedido),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cartão horizontal de um pedido aprovado que aguarda agendamento.
class _CartaoPedidoAprovado extends StatelessWidget {
  const _CartaoPedidoAprovado({
    required this.pedido,
    required this.selecionado,
    required this.aoTocar,
  });

  final PedidoModel pedido;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: aoTocar,
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selecionado ? TemasCores.marcaEscura : TemasCores.superficie,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selecionado ? TemasCores.marcaEscura : TemasCores.infoBorda,
            width: selecionado ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    pedido.nomeCliente ?? 'Cliente',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: selecionado ? TemasCores.textoInverso : TemasCores.textoPrimario,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Qtd: ${pedido.quantidade}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: selecionado ? TemasCores.infoBorda : TemasCores.infoTexto,
                  ),
                ),
              ],
            ),
            Text(
              pedido.nomeProduto ?? 'Produto',
              style: TextStyle(
                fontSize: 11,
                color: selecionado ? TemasCores.textoInversoClaro : TemasCores.textoApoioForte,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              pedido.temObservacoes ? 'Obs: ${pedido.observacoes}' : 'Sem observações',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: selecionado ? TemasCores.textoInversoSuave : TemasCores.textoTerciario,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
