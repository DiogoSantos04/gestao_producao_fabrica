import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import '../../core/formatos.dart';
import '../../models/cliente_model.dart';
import '../../models/encomenda_model.dart';
import '../../models/pedido_model.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/mouse_drag_scroll_behavior.dart';

class CriarEncomendaScreen extends StatefulWidget {
  const CriarEncomendaScreen({super.key});

  @override
  State<CriarEncomendaScreen> createState() => _CriarEncomendaScreenState();
}

class _CriarEncomendaScreenState extends State<CriarEncomendaScreen> {
  final _clientesRepo = ClientesRepository();
  final _encomendasRepo = EncomendasRepository();
  final _fluxosRepo = FluxosRepository();
  final _formKey = GlobalKey<FormState>();

  RealtimeChannel? _planeamentoSubscription;

  // Controladores dedicados para barras de scroll
  final ScrollController _previewScrollController = ScrollController();
  final ScrollController _ultimasScrollController = ScrollController();
  final ScrollController _pedidosScrollController = ScrollController();

  List<ClienteModel> _clientes = [];
  List<Map<String, dynamic>> _tiposProduto = [];
  List<Map<String, dynamic>> _previewFases = [];
  List<EncomendaModel> _ultimasEncomendas = [];
  List<PedidoModel> _pedidosAprovados = []; // 📥 Pedidos vindos da App (Estado: Aprovado)

  // Seleção e formulário
  int? _pedidoSelecionadoId; // Guarda o ID do pedido da App (se aplicável)
  String? _clienteSelecionado;
  String? _tipoProdutoSelecionado;
  String? _observacoesPedido;
  String _prioridadeSelecionada = 'Normal'; // Prioridade da ordem
  final List<String> _niveisPrioridade = ['Normal', 'Urgente', 'Crítica'];

  final _dataEntregaController = TextEditingController();
  final _quantidadeController = TextEditingController(text: '1');
  final _requisitosQualidadeController = TextEditingController(); // 📋 Novo: Campo para SOP e FAI (Requisitos de Qualidade)

  bool _isLoadingData = true;

  /// Motivo da última falha, ou `null` se correu bem. Este ecrã é um
  /// formulário: sem clientes nem tipologias carregados, os dropdowns ficam
  /// vazios e quem está a lançar produção não tem como perceber porquê.
  String? _erroCarregamento;

  /// Distingue "nunca carregou" de "falhou a atualizar o que já está no ecrã".
  bool _carregouUmaVez = false;
  bool _isLoadingPreview = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _inicializarSubscricaoRealtime();

    // ⏱️ Atualizar automaticamente o Lead Time ao alterar a quantidade
    _quantidadeController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dataEntregaController.dispose();
    _quantidadeController.dispose();
    _requisitosQualidadeController.dispose();
    _previewScrollController.dispose();
    _ultimasScrollController.dispose();
    _pedidosScrollController.dispose();
    _recarregador.descartar();
    if (_planeamentoSubscription != null) {
      _clientesRepo.client.removeChannel(_planeamentoSubscription!);
    }
    super.dispose();
  }

  // --- CÁLCULOS DO LEAD TIME (TEMPO ESTIMADO DE PRODUÇÃO) & GARGALO ---

  int _calcularTempoUnitarioMinutos() {
    int totalUnitario = 0;
    for (var f in _previewFases) {
      totalUnitario += (f['tempo_estimado'] as num? ?? 0).toInt();
    }
    return totalUnitario;
  }

  int _calcularTempoTotalMinutos() {
    final int qtd = int.tryParse(_quantidadeController.text) ?? 1;
    return _calcularTempoUnitarioMinutos() * (qtd > 0 ? qtd : 1);
  }

  String _formatarTempo(int minutos) {
    if (minutos <= 0) return '0 min';
    final int horas = minutos ~/ 60;
    final int minsRestantes = minutos % 60;

    if (horas == 0) return '${minsRestantes}m';
    if (minsRestantes == 0) return '${horas}h';
    return '${horas}h ${minsRestantes}m';
  }

  /// ⚠️ Identifica qual a fase com maior tempo de ciclo (Posto Gargalo da linha)
  Map<String, dynamic>? _obterFaseGargalo() {
    if (_previewFases.isEmpty) return null;
    var gargalo = _previewFases.first;
    for (var f in _previewFases) {
      final int tFase = (f['tempo_estimado'] as num? ?? 0).toInt();
      final int tGargalo = (gargalo['tempo_estimado'] as num? ?? 0).toInt();
      if (tFase > tGargalo) {
        gargalo = f;
      }
    }
    return gargalo;
  }

  // --- BUSCA DE DADOS & REALTIME (SUPABASE) ---

  /// Este canal escuta quatro tabelas (`pedidos_encomenda`, `tipos_produto`,
  /// `clientes`, `encomendas`) e qualquer uma delas recarregava tudo. Basta uma
  /// ordem a avançar de fase para disparar aqui um recarregamento que nada tem
  /// a ver com o que este ecrã mostra — daí o debounce.
  late final RecarregadorDebounced _recarregador = RecarregadorDebounced(
    aoRecarregar: _carregarDados,
    janela: janelaRealtimeCarteira,
    tetoEspera: tetoRealtimeCarteira,
  );

  void _inicializarSubscricaoRealtime() {
    _planeamentoSubscription = _clientesRepo.escutarPlaneamento(
      'db-planeamento-realtime',
      _recarregador.pedir,
    );
  }

  Future<void> _carregarDados() async {
    try {
      final clientesData = await _clientesRepo.obterParaSelecao();
      final produtosData = await _fluxosRepo.obterTipologiasParaSelecao();

      // Buscar Pedidos da App que foram Aprovados e aguardam Agendamento de Produção
      final pedidosData = await _clientesRepo.obterPedidosAprovados();

      final encomendasData = await _encomendasRepo.obterUltimasLancadas();

      if (mounted) {
        setState(() {
          _clientes = clientesData;
          _tiposProduto = produtosData;
          _pedidosAprovados = pedidosData;
          _ultimasEncomendas = encomendasData;
          _isLoadingData = false;
          _erroCarregamento = null;
          _carregouUmaVez = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _erroCarregamento = descreverErro(e);
        });
      }
    }
  }

  Future<void> _carregarPreviewFluxo(String tipoProdutoId) async {
    setState(() {
      _isLoadingPreview = true;
      _previewFases = [];
    });

    try {
      final fasesData = await _fluxosRepo.obterFasesParaPreview(int.parse(tipoProdutoId));

      if (mounted) {
        setState(() {
          _previewFases = fasesData;
          _isLoadingPreview = false;
        });
        if (_previewScrollController.hasClients) {
          _previewScrollController.jumpTo(0);
        }
      }
    } catch (e) {
      _mostrarMensagem('Erro ao gerar pré-visualização: $e', eErro: true);
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  // --- LÓGICA DE SELEÇÃO AUTOMÁTICA DO PEDIDO ---

  void _selecionarPedidoParaAgendar(PedidoModel pedido) {
    setState(() {
      _pedidoSelecionadoId = pedido.id;
      _clienteSelecionado = pedido.clienteId?.toString();
      _tipoProdutoSelecionado = pedido.tipoProdutoId?.toString();
      _quantidadeController.text = pedido.quantidade.toString();
      _observacoesPedido = pedido.observacoes;
      _requisitosQualidadeController.text = pedido.observacoes ?? ''; // Preenche o campo de qualidade
      _prioridadeSelecionada = 'Normal';
    });

    if (_tipoProdutoSelecionado != null) {
      _carregarPreviewFluxo(_tipoProdutoSelecionado!);
    }
  }

  void _limparSelecaoPedido() {
    setState(() {
      _pedidoSelecionadoId = null;
      _clienteSelecionado = null;
      _tipoProdutoSelecionado = null;
      _observacoesPedido = null;
      _dataEntregaController.clear();
      _quantidadeController.text = '1';
      _requisitosQualidadeController.clear();
      _prioridadeSelecionada = 'Normal';
      _previewFases = [];
    });
  }

  // --- REGRAS DE NEGÓCIO ---

  String _gerarCodigoRastreio() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final sufixo = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    return 'TRC-$sufixo';
  }

  Future<void> _lancarEncomenda() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final int prodId = int.parse(_tipoProdutoSelecionado!);

      final faseInicialData = await _fluxosRepo.obterFaseInicial(prodId);

      if (faseInicialData == null) {
        throw Exception('Não foi encontrada nenhuma fase inicial (Ordem 1) definida para este tipo de produto.');
      }

      final codigoRastreio = _gerarCodigoRastreio();

      // 1. Criar a Ordem Oficial de Produção com Prioridade e Instruções de Qualidade
      await _encomendasRepo.lancar(
        codigoRastreio: codigoRastreio,
        dataEntrega: _dataEntregaController.text,
        clienteId: int.parse(_clienteSelecionado!),
        tipoProdutoId: prodId,
        faseInicialId: faseInicialData['id'] as int,
        quantidade: int.parse(_quantidadeController.text),
        prioridade: _prioridadeSelecionada,
        observacoes: _requisitosQualidadeController.text.trim(),
      );

      // 2. Se a ordem veio de um Pedido da App, atualizar o estado do pedido para 'Em Produção'
      if (_pedidoSelecionadoId != null) {
        await _clientesRepo.marcarPedidoEmProducao(_pedidoSelecionadoId!);
      }

      _mostrarMensagem('Ordem $codigoRastreio lançada para produção com prioridade $_prioridadeSelecionada!');

      _limparSelecaoPedido();
      _carregarDados();
    } catch (e) {
      _mostrarMensagem('Erro ao lançar encomenda: ${e.toString().replaceAll('Exception: ', '')}', eErro: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: TemasCores.acaoPrincipal,
              onPrimary: TemasCores.textoInverso,
              onSurface: TemasCores.textoPrimario,
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataEscolhida != null) {
      setState(() {
        _dataEntregaController.text = "${dataEscolhida.year}-${dataEscolhida.month.toString().padLeft(2, '0')}-${dataEscolhida.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _mostrarMensagem(String msg, {bool eErro = false}) {
    if (mounted) {
      context.mostrarMensagem(msg, eErro: eErro);
    }
  }

  // --- UI CONSTRUÇÃO ---

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    if (_isLoadingData) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Sem clientes nem tipologias, o formulário não é utilizável: mais vale
    // dizê-lo e oferecer o botão de repetir do que mostrar dropdowns vazios.
    if (_erroCarregamento != null && !_carregouUmaVez) {
      return Scaffold(
        backgroundColor: TemasCores.fundoEcra,
        body: EstadoErro(
          titulo: 'Não foi possível carregar os dados de planeamento',
          detalhe: _erroCarregamento,
          aoRepetir: () {
            setState(() => _isLoadingData = true);
            _carregarDados();
          },
        ),
      );
    }

    return ScrollConfiguration(
      behavior: MouseDragScrollBehavior(),
      child: Scaffold(
        backgroundColor: TemasCores.fundoEcra,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Planeamento & Lançamento de Produção',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              if (_erroCarregamento != null)
                EstadoErro.compacto(
                  titulo: 'Os dados podem estar desatualizados — falhou a última atualização.',
                  detalhe: _erroCarregamento,
                  aoRepetir: _carregarDados,
                ),
              const SizedBox(height: 20),
              Expanded(
                child: eDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 4, child: SingleChildScrollView(child: _buildPainelEsquerdoForm())),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                Expanded(child: _buildPainelDireitoPreview(eDesktop: true)),
                                const SizedBox(height: 24),
                                Expanded(child: _buildPainelDireitoUltimas(eDesktop: true)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildPainelEsquerdoForm(),
                            const SizedBox(height: 24),
                            _buildPainelDireitoPreview(eDesktop: false),
                            const SizedBox(height: 24),
                            _buildPainelDireitoUltimas(eDesktop: false),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cartão horizontal de um pedido aprovado que aguarda agendamento.
  Widget _buildCartaoPedidoAprovado(PedidoModel ped) {
    final bool selecionado = _pedidoSelecionadoId == ped.id;

    return GestureDetector(
      onTap: () => _selecionarPedidoParaAgendar(ped),
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
                    ped.nomeCliente ?? 'Cliente',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: selecionado ? TemasCores.textoInverso : TemasCores.textoPrimario,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Qtd: ${ped.quantidade}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: selecionado ? TemasCores.infoBorda : TemasCores.infoTexto,
                  ),
                ),
              ],
            ),
            Text(
              ped.nomeProduto ?? 'Produto',
              style: TextStyle(
                fontSize: 11,
                color: selecionado ? TemasCores.textoInversoClaro : TemasCores.textoApoioForte,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              ped.temObservacoes ? 'Obs: ${ped.observacoes}' : 'Sem observações',
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

  // --- COLUNA DA ESQUERDA: PEDIDOS APROVADOS & FORMULÁRIO DE LANÇAMENTO ---
  Widget _buildPainelEsquerdoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- SECÇÃO: PEDIDOS DA APP AGUARDANDO AGENDAMENTO ---
        if (_pedidosAprovados.isNotEmpty) ...[
          Card(
            color: TemasCores.infoFundo.withOpacity(0.6),
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
                      Row(
                        children: [
                          const Icon(Icons.move_to_inbox_rounded, color: TemasCores.infoTextoForte, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Pedidos Aprovados (App)',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: TemasCores.infoTextoIntenso),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: TemasCores.infoTexto, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          '${_pedidosAprovados.length} pendentes',
                          style: const TextStyle(color: TemasCores.textoInverso, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Clique num pedido para preencher automaticamente o formulário de agendamento',
                    style: const TextStyle(fontSize: 12, color: TemasCores.infoTextoForte),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    height: 110,
                    child: Scrollbar(
                      controller: _pedidosScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _pedidosScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: _pedidosAprovados.length,
                        itemBuilder: (context, idx) => _buildCartaoPedidoAprovado(_pedidosAprovados[idx]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // --- FORMULÁRIO PRINCIPAL DE LANÇAMENTO ---
        Card(
          color: TemasCores.superficie,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: TemasCores.borda),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lançar Nova Encomenda',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pedidoSelecionadoId != null
                                ? 'Agendando pedido vindo da Aplicação B2B'
                                : 'Preencha os dados para iniciar uma nova ordem de produção',
                            style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
                          ),
                        ],
                      ),
                      if (_pedidoSelecionadoId != null)
                        TextButton.icon(
                          onPressed: _limparSelecaoPedido,
                          icon: const Icon(Icons.close_rounded, size: 16, color: TemasCores.erroVivo),
                          label: const Text('Entrada Manual', style: TextStyle(color: TemasCores.erroVivo, fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_pedidoSelecionadoId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TemasCores.avisoFundo,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: TemasCores.avisoBorda),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.link_rounded, color: TemasCores.avisoTextoForte, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vinculado ao Pedido #${_pedidoSelecionadoId!} da App${_observacoesPedido != null && _observacoesPedido!.isNotEmpty ? " • Nota: $_observacoesPedido" : ""}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.avisoTextoForte),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  _buildCampoCliente(),
                  const SizedBox(height: 20),
                  _buildCampoTipoProduto(),
                  const SizedBox(height: 20),
                  _buildCamposPrazoEQuantidade(),
                  const SizedBox(height: 20),
                  _buildCampoPrioridade(),
                  const SizedBox(height: 20),
                  _buildCampoRequisitosQualidade(),
                  const SizedBox(height: 32),
                  _buildBotaoLancar(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- CAMPOS DO FORMULÁRIO ---
  // Extraídos de um único método de 401 linhas.

  /// Decoração comum a todos os campos do formulário.
  InputDecoration _decoracaoCampo({String? hintText, Widget? suffixIcon, EdgeInsets? padding}) {
    return InputDecoration(
      hintText: hintText,
      suffixIcon: suffixIcon,
      fillColor: TemasCores.superficieSuave,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
    );
  }

  Widget _rotuloCampo(String texto) {
    return Text(texto,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario));
  }

  Widget _buildCampoCliente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rotuloCampo('Seleção de Cliente'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _clienteSelecionado,
          decoration: _decoracaoCampo(hintText: 'Selecione um cliente'),
          items: _clientes.map((c) {
            return DropdownMenuItem<String>(
              value: c.id.toString(),
              child: Text(c.nomeCliente),
            );
          }).toList(),
          onChanged: (val) => setState(() => _clienteSelecionado = val),
          validator: (val) => val == null ? 'Selecione um cliente' : null,
        ),
      ],
    );
  }

  Widget _buildCampoTipoProduto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rotuloCampo('Tipo de Produto'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _tipoProdutoSelecionado,
          decoration: _decoracaoCampo(hintText: 'Selecione o tipo de produto'),
          items: _tiposProduto.map((p) {
            return DropdownMenuItem<String>(
              value: p['id'].toString(),
              child: Text(p['nome_tipo_produto'] ?? ''),
            );
          }).toList(),
          onChanged: (val) {
            setState(() => _tipoProdutoSelecionado = val);
            if (val != null) _carregarPreviewFluxo(val);
          },
          validator: (val) => val == null ? 'Selecione um tipo de produto' : null,
        ),
      ],
    );
  }

  Widget _buildCamposPrazoEQuantidade() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rotuloCampo('Data Prevista de Entrega'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataEntregaController,
                readOnly: true,
                onTap: () => _selecionarData(context),
                decoration: _decoracaoCampo(
                  hintText: 'aaaa-mm-dd',
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: TemasCores.textoSecundario),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Indique o prazo' : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rotuloCampo('Quantidade'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _quantidadeController,
                keyboardType: TextInputType.number,
                decoration: _decoracaoCampo(
                  hintText: 'Ex: 100',
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Obrigatório';
                  if (int.tryParse(val) == null || int.parse(val) <= 0) return 'Inválido';
                  return null;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Ícone e cor de cada nível de prioridade.
  ({IconData icone, Color cor}) _estiloPrioridade(String prio) {
    return switch (prio) {
      'Urgente' => (icone: Icons.warning_amber_rounded, cor: TemasCores.alertaTexto),
      'Crítica' => (icone: Icons.local_fire_department_rounded, cor: TemasCores.erroTextoForte),
      _ => (icone: Icons.circle_outlined, cor: TemasCores.textoApoioForte),
    };
  }

  Widget _buildCampoPrioridade() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rotuloCampo('Prioridade da Ordem'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _prioridadeSelecionada,
          decoration: _decoracaoCampo(),
          items: _niveisPrioridade.map((prio) {
            final estilo = _estiloPrioridade(prio);
            return DropdownMenuItem<String>(
              value: prio,
              child: Row(
                children: [
                  Icon(estilo.icone, size: 16, color: estilo.cor),
                  const SizedBox(width: 8),
                  Text(
                    prio,
                    style: TextStyle(
                      fontWeight: prio != 'Normal' ? FontWeight.bold : FontWeight.normal,
                      color: estilo.cor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _prioridadeSelecionada = val);
          },
        ),
      ],
    );
  }

  Widget _buildCampoRequisitosQualidade() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rotuloCampo('Instruções Técnicas & Requisitos de Qualidade (SOP / FAI)'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _requisitosQualidadeController,
          maxLines: 2,
          decoration: _decoracaoCampo(
            hintText: 'Ex: Tolerância crítica na furação; Validação da 1ª peça (FAI); Cor RAL 3020.',
            padding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }

  Widget _buildBotaoLancar() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _lancarEncomenda,
        style: ElevatedButton.styleFrom(
          backgroundColor: TemasCores.marcaEscura,
          foregroundColor: TemasCores.textoInverso,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        icon: _isSaving
            ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(color: TemasCores.textoInverso, strokeWidth: 2))
            : const Icon(Icons.rocket_launch_outlined, size: 18),
        label: Text(
          _pedidoSelecionadoId != null
              ? 'Lançar Pedido da App para Produção'
              : 'Lançar Encomenda Manual',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
        ),
      ),
    );
  }

  /// Cartão com a carga total estimada, o posto gargalo e o alerta de carga elevada.
  Widget _buildCartaoLeadTime({
    required int tempoTotalMins,
    required int tempoUnitarioMins,
    required Map<String, dynamic>? gargalo,
    required bool eCargaElevada,
  }) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 18, color: TemasCores.resumoTexto),
                  const SizedBox(width: 8),
                  Text(
                    'Carga Total Estimada:',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.resumoTexto),
                  ),
                ],
              ),
              Text(
                '${_formatarTempo(tempoTotalMins)} (${_formatarTempo(tempoUnitarioMins)}/unid)',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.resumoTextoForte),
              ),
            ],
          ),

          // ⚠️ Deteção do posto gargalo
          if (gargalo != null) ...[
            const Divider(height: 14),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 15, color: TemasCores.avisoTextoForte),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gargalo: ${gargalo['nome_fase_padrao']} (${gargalo['tempo_estimado']} min no ${gargalo['posto_trabalho'] ?? 'Posto'})',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.avisoTextoForte),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // 🔴 Alerta de carga elevada (mais de 8 horas de fábrica)
          if (eCargaElevada) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration:
                  BoxDecoration(color: TemasCores.alertaFundoForte, borderRadius: BorderRadius.circular(4)),
              child: Text(
                '⚡ Esta encomenda representa uma carga de fabrico elevada (+8 horas).',
                style: TextStyle(
                    fontSize: 10, color: TemasCores.alertaTextoForte, fontWeight: FontWeight.w600),
              ),
            ),
          ]
        ],
      ),
    );
  }

  // --- COLUNA DA DIREITA (CIMA): PRÉ-VISUALIZAÇÃO & CÁLCULO DE LEAD TIME / GARGALO ---
  Widget _buildPainelDireitoPreview({required bool eDesktop}) {
    Widget conteudo;

    if (_isLoadingPreview) {
      conteudo = const Center(child: CircularProgressIndicator());
    } else if (_previewFases.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Selecione um tipo de produto para ver o fluxo',
          style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
        ),
      );
    } else {
      final int tempoTotalMins = _calcularTempoTotalMinutos();
      final int tempoUnitarioMins = _calcularTempoUnitarioMinutos();
      final Map<String, dynamic>? gargalo = _obterFaseGargalo();
      final bool eCargaElevada = tempoTotalMins > 480; // Mais de 8 horas de fábrica

      conteudo = Column(
        children: [
          _buildCartaoLeadTime(
            tempoTotalMins: tempoTotalMins,
            tempoUnitarioMins: tempoUnitarioMins,
            gargalo: gargalo,
            eCargaElevada: eCargaElevada,
          ),

          // LISTA DE FASES DO FLUXO
          Expanded(
            child: Scrollbar(
              controller: _previewScrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _previewScrollController,
                itemCount: _previewFases.length,
                padding: const EdgeInsets.only(right: 12),
                itemBuilder: (context, idx) {
                  final f = _previewFases[idx];
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
                          decoration: BoxDecoration(color: TemasCores.superficieEscura, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            '${f['ordem']}',
                            style: const TextStyle(color: TemasCores.textoInverso, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f['nome_fase_padrao'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              if (f['posto_trabalho'] != null && f['posto_trabalho'].toString().isNotEmpty)
                                Text(
                                  'Posto: ${f['posto_trabalho']}',
                                  style: const TextStyle(color: TemasCores.textoApoio, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '⏱️ ${f['tempo_estimado']} min',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.textoApoio),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pré-visualização do Fluxo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            ),
            const SizedBox(height: 4),
            Text(
              'Fases que a encomenda irá seguir automaticamente',
              style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
            ),
            const SizedBox(height: 16),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 320, child: conteudo),
          ],
        ),
      ),
    );
  }

  /// Cores do badge de prioridade. `Normal` não mostra badge.
  ({Color texto, Color fundo}) _coresPrioridade(String prioridade) {
    return switch (prioridade) {
      'Urgente' => (texto: TemasCores.alertaTextoForte, fundo: TemasCores.alertaFundo),
      'Crítica' => (texto: TemasCores.erroTextoIntenso, fundo: TemasCores.erroFundo),
      _ => (texto: TemasCores.textoApoioForte, fundo: TemasCores.superficieSuave),
    };
  }

  /// Cartão de uma das últimas ordens lançadas.
  Widget _buildCartaoUltimaEncomenda(EncomendaModel enc) {
    final idFormated = Formatos.referenciaOrdem(
      enc.id,
      criadaEm: enc.createdAt?.toIso8601String(),
    );
    final cores = _coresPrioridade(enc.prioridade);

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
                      idFormated,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: TemasCores.superficieSuave, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        enc.codigoRastreio ?? '',
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.bold, color: TemasCores.textoApoioForte),
                      ),
                    ),
                    if (enc.prioridade != 'Normal')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration:
                            BoxDecoration(color: cores.fundo, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          enc.prioridade.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9, fontWeight: FontWeight.bold, color: cores.texto),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(enc.nomeCliente ?? 'Desconhecido',
                    style: const TextStyle(color: TemasCores.textoApoioForte, fontSize: 12)),
                Text(enc.nomeProduto ?? 'N/A',
                    style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                enc.dataEntregaIso ?? '',
                style: const TextStyle(fontSize: 11, color: TemasCores.textoDesativado, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration:
                    BoxDecoration(color: TemasCores.infoFundo, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Qtd: ${enc.quantidade}',
                  style: const TextStyle(fontSize: 10, color: TemasCores.infoTexto, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- COLUNA DA DIREITA (BAIXO): ÚLTIMAS ENCOMENDAS ---
  Widget _buildPainelDireitoUltimas({required bool eDesktop}) {
    Widget conteudo;

    if (_ultimasEncomendas.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Nenhuma encomenda registada recentemente.',
          style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _ultimasScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _ultimasScrollController,
          itemCount: _ultimasEncomendas.length,
          padding: const EdgeInsets.only(right: 12),
          itemBuilder: (context, index) => _buildCartaoUltimaEncomenda(_ultimasEncomendas[index]),
        ),
      );
    }

    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Últimas Encomendas Lançadas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            ),
            const SizedBox(height: 16),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 400, child: conteudo),
          ],
        ),
      ),
    );
  }
}