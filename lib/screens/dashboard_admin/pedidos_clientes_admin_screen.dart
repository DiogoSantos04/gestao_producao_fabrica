import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/pedido_model.dart';
import '../../repositories/clientes_repository.dart';

class PedidosClientesAdminScreen extends StatefulWidget {
  const PedidosClientesAdminScreen({super.key});

  @override
  State<PedidosClientesAdminScreen> createState() => _PedidosClientesAdminScreenState();
}

class _PedidosClientesAdminScreenState extends State<PedidosClientesAdminScreen> {
  final _clientesRepo = ClientesRepository();
  List<PedidoModel> _pedidos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarPedidos();
  }

  Future<void> _carregarPedidos() async {
    try {
      final data = await _clientesRepo.obterPedidos();

      if (mounted) {
        setState(() {
          _pedidos = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar pedidos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _gerarCodigoRastreio() {
    final rand = math.Random();
    final codigo = List.generate(6, (_) => rand.nextInt(16).toRadixString(16).toUpperCase()).join();
    return 'TRC-$codigo';
  }

  /// Cartão de um pedido de cliente.
  ///
  /// Nota sobre as cores: o estado "Aprovado" mostra-se em verde e **todos os
  /// outros estados não-pendentes em vermelho**, incluindo "Em Produção". Este
  /// comportamento vinha do código original e foi preservado deliberadamente
  /// neste refactor — ver a nota em ARQUITETURA_REFACTOR.md.
  Widget _buildPedidoCard(PedidoModel p) {
    final bool isPendente = p.estado.aguardaDecisao;
    final bool isAprovado = p.estado == EstadoPedido.aprovado;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _buildIconeEstado(isPendente: isPendente, isAprovado: isAprovado),
            const SizedBox(width: 16),
            Expanded(child: _buildResumoPedido(p)),
            if (isPendente)
              _buildAcoesPendente(p)
            else
              _buildBadgeEstado(p, isAprovado: isAprovado),
          ],
        ),
      ),
    );
  }

  Widget _buildIconeEstado({required bool isPendente, required bool isAprovado}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPendente
            ? Colors.amber.shade50
            : (isAprovado ? Colors.green.shade50 : Colors.red.shade50),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isPendente
            ? Icons.pending_actions
            : (isAprovado ? Icons.check_circle_outline : Icons.cancel_outlined),
        color: isPendente ? Colors.amber.shade800 : (isAprovado ? Colors.green : Colors.red),
      ),
    );
  }

  Widget _buildResumoPedido(PedidoModel p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${p.nomeCliente ?? 'Cliente'} — ${p.nomeProduto ?? 'Artigo'} (${p.quantidade} unid.)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        if (p.temObservacoes) ...[
          const SizedBox(height: 4),
          Text(
            'Obs: ${p.observacoes}',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ],
    );
  }

  Widget _buildAcoesPendente(PedidoModel p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () => _rejeitarPedido(p.id),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Rejeitar'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _aprovarELancarEncomenda(p),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.rocket_launch, size: 18),
          label: const Text('Aprovar e Lançar'),
        ),
      ],
    );
  }

  Widget _buildBadgeEstado(PedidoModel p, {required bool isAprovado}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isAprovado ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        p.estado.etiqueta.toUpperCase(),
        style: TextStyle(
          color: isAprovado ? Colors.green.shade900 : Colors.red.shade900,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _aprovarELancarEncomenda(PedidoModel pedido) async {
    DateTime dataEntregaSelecionada = DateTime.now().add(const Duration(days: 15));

    // Modal para selecionar data de entrega prevista antes do lançamento
    final DateTime? dataPick = await showDatePicker(
      context: context,
      initialDate: dataEntregaSelecionada,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: 'SELECIONE A DATA PREVISTA DE ENTREGA',
    );

    if (dataPick == null) return; // Cancelou a operação
    dataEntregaSelecionada = dataPick;

    try {
      final String codigoRastreio = _gerarCodigoRastreio();
      final String dataFormatted =
          "${dataEntregaSelecionada.year}-${dataEntregaSelecionada.month.toString().padLeft(2, '0')}-${dataEntregaSelecionada.day.toString().padLeft(2, '0')}";

      // Lançar a ordem, atualizar o pedido e notificar o cliente corre tudo numa
      // única transação no servidor. A notificação usa a ligação real
      // `clientes.utilizador_id` — antes procurava-se o utilizador comparando
      // `nome_utilizador` com `nome_cliente`, o que falhava ou acertava na pessoa
      // errada perante nomes repetidos ou ligeiramente diferentes.
      await _clientesRepo.aprovarPedido(
        pedidoId: pedido.id,
        dataEntrega: dataFormatted,
        codigoRastreio: codigoRastreio,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Encomenda $codigoRastreio lançada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _carregarPedidos();
      }
    } catch (e) {
      debugPrint('Erro ao lançar encomenda: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejeitarPedido(int pedidoId) async {
    try {
      await _clientesRepo.rejeitarPedido(pedidoId);
      _carregarPedidos();
    } catch (e) {
      debugPrint('Erro ao rejeitar pedido: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pedidos de Encomenda de Clientes',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Analise e aprove as solicitações submetidas pelos clientes comerciais.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _carregarPedidos();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Expanded(
                    child: _pedidos.isEmpty
                        ? const Center(child: Text('Nenhum pedido de encomenda registado.'))
                        : ListView.builder(
                            itemCount: _pedidos.length,
                            itemBuilder: (context, index) => _buildPedidoCard(_pedidos[index]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}