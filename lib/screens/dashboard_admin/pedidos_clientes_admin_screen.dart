import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/pedido_model.dart';
import '../../repositories/clientes_repository.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/etiqueta_estado.dart';

class PedidosClientesAdminScreen extends StatefulWidget {
  const PedidosClientesAdminScreen({super.key});

  @override
  State<PedidosClientesAdminScreen> createState() => _PedidosClientesAdminScreenState();
}

class _PedidosClientesAdminScreenState extends State<PedidosClientesAdminScreen> {
  final _clientesRepo = ClientesRepository();
  List<PedidoModel> _pedidos = [];
  bool _isLoading = true;

  /// Motivo da última falha, ou `null` se correu bem. Um pedido de cliente por
  /// decidir que não aparece porque a leitura falhou fica por decidir sem que
  /// ninguém saiba — "nenhum pedido registado" não podia continuar a ser o que
  /// se vê nesse caso.
  String? _erroCarregamento;

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
          _erroCarregamento = null;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar pedidos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _erroCarregamento = descreverErro(e);
        });
      }
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
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
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
            ? TemasCores.avisoFundo
            : (isAprovado ? TemasCores.sucessoFundo : TemasCores.erroFundo),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isPendente
            ? Icons.pending_actions
            : (isAprovado ? Icons.check_circle_outline : Icons.cancel_outlined),
        color: isPendente ? TemasCores.avisoTexto : (isAprovado ? TemasCores.sucesso : TemasCores.erro),
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
            style: const TextStyle(color: TemasCores.textoSecundarioFrio, fontSize: 13),
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
          style: OutlinedButton.styleFrom(foregroundColor: TemasCores.erro),
          child: const Text('Rejeitar'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _aprovarELancarEncomenda(p),
          style: ElevatedButton.styleFrom(
            backgroundColor: TemasCores.marcaAcento,
            foregroundColor: TemasCores.textoInverso,
          ),
          icon: const Icon(Icons.rocket_launch, size: 18),
          label: const Text('Aprovar e Lançar'),
        ),
      ],
    );
  }

  Widget _buildBadgeEstado(PedidoModel p, {required bool isAprovado}) {
    return EtiquetaEstado.destacada(
      rotulo: p.estado.etiqueta.toUpperCase(),
      fundo: isAprovado ? TemasCores.sucessoFundoForte : TemasCores.erroFundoForte,
      texto: isAprovado ? TemasCores.sucessoTextoIntenso : TemasCores.erroTextoIntenso,
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
        context.mostrarMensagem('Encomenda $codigoRastreio lançada com sucesso!');
        _carregarPedidos();
      }
    } catch (e) {
      debugPrint('Erro ao lançar encomenda: $e');
      if (mounted) {
        context.mostrarMensagem('Erro ao processar: $e', eErro: true);
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
      backgroundColor: TemasCores.fundoEcraFrio,
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
                              color: TemasCores.textoPrimarioFrio,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Analise e aprove as solicitações submetidas pelos clientes comerciais.',
                            style: TextStyle(fontSize: 14, color: TemasCores.textoSecundarioFrio),
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

                  if (_erroCarregamento != null && _pedidos.isNotEmpty)
                    EstadoErro.compacto(
                      titulo: 'A lista pode estar desatualizada — falhou a última atualização.',
                      detalhe: _erroCarregamento,
                      aoRepetir: _carregarPedidos,
                    ),

                  Expanded(
                    child: _pedidos.isEmpty
                        ? (_erroCarregamento != null
                            ? EstadoErro(
                                titulo: 'Não foi possível carregar os pedidos de encomenda',
                                detalhe: _erroCarregamento,
                                aoRepetir: () {
                                  setState(() => _isLoading = true);
                                  _carregarPedidos();
                                },
                              )
                            : const Center(child: Text('Nenhum pedido de encomenda registado.')))
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