import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import '../../models/cliente_model.dart';
import '../../models/encomenda_model.dart';
import '../../models/pedido_model.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/formulario_lancamento.dart';
import 'widgets/mouse_drag_scroll_behavior.dart';
import 'widgets/painel_pedidos_aprovados.dart';
import 'widgets/painel_preview_fluxo.dart';
import 'widgets/painel_ultimas_encomendas.dart';

/// Planeamento e lançamento de ordens de produção.
///
/// À esquerda, os pedidos da App aprovados e o formulário de lançamento; à
/// direita, a pré-visualização do fluxo escolhido e as últimas ordens lançadas.
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

  List<ClienteModel> _clientes = [];
  List<Map<String, dynamic>> _tiposProduto = [];
  List<Map<String, dynamic>> _previewFases = [];
  List<EncomendaModel> _ultimasEncomendas = [];

  /// Pedidos vindos da App já aprovados, à espera de agendamento.
  List<PedidoModel> _pedidosAprovados = [];

  /// Pedido da App que originou o lançamento em curso, ou `null` se manual.
  int? _pedidoSelecionadoId;
  String? _clienteSelecionado;
  String? _tipoProdutoSelecionado;
  String? _observacoesPedido;
  String _prioridadeSelecionada = 'Normal';

  final _dataEntregaController = TextEditingController();
  final _quantidadeController = TextEditingController(text: '1');
  final _requisitosQualidadeController = TextEditingController();

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

    // O lead time depende da quantidade: recalcular à medida que é escrita.
    _quantidadeController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dataEntregaController.dispose();
    _quantidadeController.dispose();
    _requisitosQualidadeController.dispose();
    _recarregador.descartar();
    if (_planeamentoSubscription != null) {
      _clientesRepo.client.removeChannel(_planeamentoSubscription!);
    }
    super.dispose();
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
      _requisitosQualidadeController.text = pedido.observacoes ?? '';
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
        throw Exception(
            'Não foi encontrada nenhuma fase inicial (Ordem 1) definida para este tipo de produto.');
      }

      final codigoRastreio = _gerarCodigoRastreio();

      // 1. Criar a ordem oficial de produção.
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

      // 2. Se veio de um pedido da App, marcá-lo como 'Em Produção'.
      if (_pedidoSelecionadoId != null) {
        await _clientesRepo.marcarPedidoEmProducao(_pedidoSelecionadoId!);
      }

      _mostrarMensagem(
          'Ordem $codigoRastreio lançada para produção com prioridade $_prioridadeSelecionada!');

      _limparSelecaoPedido();
      _carregarDados();
    } catch (e) {
      _mostrarMensagem(
          'Erro ao lançar encomenda: ${e.toString().replaceAll('Exception: ', '')}',
          eErro: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selecionarData() async {
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

    if (dataEscolhida != null && mounted) {
      setState(() {
        _dataEntregaController.text = '${dataEscolhida.year}-'
            '${dataEscolhida.month.toString().padLeft(2, '0')}-'
            '${dataEscolhida.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _mostrarMensagem(String msg, {bool eErro = false}) {
    if (mounted) {
      context.mostrarMensagem(msg, eErro: eErro);
    }
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final bool eDesktop = MediaQuery.of(context).size.width > 950;

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
                child: eDesktop ? _layoutDesktop() : _layoutEstreito(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layoutDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 4, child: SingleChildScrollView(child: _colunaFormulario())),
        const SizedBox(width: 24),
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _painelPreview(eDesktop: true)),
              const SizedBox(height: 24),
              Expanded(child: _painelUltimas(eDesktop: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _layoutEstreito() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _colunaFormulario(),
          const SizedBox(height: 24),
          _painelPreview(eDesktop: false),
          const SizedBox(height: 24),
          _painelUltimas(eDesktop: false),
        ],
      ),
    );
  }

  Widget _colunaFormulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pedidosAprovados.isNotEmpty) ...[
          PainelPedidosAprovados(
            pedidos: _pedidosAprovados,
            pedidoSelecionadoId: _pedidoSelecionadoId,
            aoSelecionar: _selecionarPedidoParaAgendar,
          ),
          const SizedBox(height: 20),
        ],
        FormularioLancamento(
          formKey: _formKey,
          clientes: _clientes,
          tiposProduto: _tiposProduto,
          clienteSelecionado: _clienteSelecionado,
          tipoProdutoSelecionado: _tipoProdutoSelecionado,
          prioridadeSelecionada: _prioridadeSelecionada,
          dataEntregaController: _dataEntregaController,
          quantidadeController: _quantidadeController,
          requisitosQualidadeController: _requisitosQualidadeController,
          pedidoSelecionadoId: _pedidoSelecionadoId,
          observacoesPedido: _observacoesPedido,
          isSaving: _isSaving,
          aoMudarCliente: (val) => setState(() => _clienteSelecionado = val),
          aoMudarTipoProduto: (val) {
            setState(() => _tipoProdutoSelecionado = val);
            if (val != null) _carregarPreviewFluxo(val);
          },
          aoMudarPrioridade: (val) => setState(() => _prioridadeSelecionada = val),
          aoEscolherData: _selecionarData,
          aoLimparSelecao: _limparSelecaoPedido,
          aoLancar: _lancarEncomenda,
        ),
      ],
    );
  }

  Widget _painelPreview({required bool eDesktop}) {
    return PainelPreviewFluxo(
      fases: _previewFases,
      quantidade: int.tryParse(_quantidadeController.text) ?? 1,
      aCarregar: _isLoadingPreview,
      eDesktop: eDesktop,
    );
  }

  Widget _painelUltimas({required bool eDesktop}) {
    return PainelUltimasEncomendas(
      encomendas: _ultimasEncomendas,
      eDesktop: eDesktop,
    );
  }
}
