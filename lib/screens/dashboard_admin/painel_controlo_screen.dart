import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, PostgresChangePayload, RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/paginacao.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import 'widgets/cartao_ordem_producao.dart';
import '../../widgets/rodape_paginacao.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../models/fase_model.dart';
import '../../models/reason_code_model.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/utilizadores_repository.dart';
import '../../widgets/estado_erro.dart';
import 'dialogos/dialogo_cancelar_ordem.dart';
import 'dialogos/dialogo_editar_ordem.dart';
import 'dialogos/dialogo_historico_ordem.dart';
import 'dialogos/dialogo_line_clearance.dart';
import 'dialogos/dialogo_registo_tecnico.dart';
import 'dialogos/dialogo_wip_hold.dart';

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({
    super.key,
    this.filtroInicial = FiltroEstadoOrdem.todos,
  });

  /// Filtro com que o ecrã abre, quando é aberto a partir de um KPI do
  /// dashboard. O utilizador pode mudá-lo logo a seguir como em qualquer
  /// outra visita.
  final FiltroEstadoOrdem filtroInicial;

  @override
  State<PainelControloScreen> createState() => _PainelControloScreenState();
}

class _PainelControloScreenState extends State<PainelControloScreen> {
  final _encomendasRepo = EncomendasRepository();
  final _fluxosRepo = FluxosRepository();
  final _utilizadoresRepo = UtilizadoresRepository();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// As ordens já carregadas — a primeira página mais o que o scroll acrescentou.
  ///
  /// Não existe aqui nenhuma lista "filtrada": o filtro e a pesquisa são
  /// aplicados pelo servidor. Enquanto se carregava a tabela inteira era
  /// indiferente, mas com paginação filtrar em memória faria a pesquisa mentir —
  /// encontraria apenas o que já tivesse descido para o ecrã.
  List<EncomendaModel> _encomendas = [];
  List<ReasonCodeModel> _reasonCodes = [];
  List<Map<String, dynamic>> _tecnicosUtilizadores = []; // Lista de técnicos/utilizadores da empresa
  Map<int, List<FaseModel>> _fasesPorProduto = {};

  late FiltroEstadoOrdem _filtroEstado = widget.filtroInicial;
  bool _isLoading = true;
  bool _aCarregarMais = false;
  bool _temMais = false;

  /// Motivo da última falha a carregar a lista, ou `null` se correu bem.
  ///
  /// Sem isto, uma falha de rede deixava a lista vazia com a mensagem "não
  /// existem ordens correspondentes à pesquisa" — que é uma afirmação sobre a
  /// fábrica, não sobre a ligação. É a diferença entre "não há trabalho" e "não
  /// sabemos".
  String? _erroCarregamento;

  /// Falha a acrescentar a página seguinte. Vive à parte porque o que já está
  /// carregado continua válido: só o rodapé muda.
  String? _erroPaginacao;

  /// Adia a ida ao servidor enquanto o utilizador ainda está a escrever.
  Timer? _debouncePesquisa;

  /// Um único canal cobre `encomendas` e `incidencias` — antes eram dois canais
  /// separados que disparavam o mesmo recarregamento.
  RealtimeChannel? _encomendasSubscription;

  @override
  void initState() {
    super.initState();
    _carregarAuxiliares();
    _carregarEncomendas(mostrarLoader: true).then((_) => _ativarSubscricaoRealtime());
    _searchController.addListener(_aoEscreverPesquisa);
    _scrollController.addListener(_aoDeslizar);
  }

  @override
  void dispose() {
    if (_encomendasSubscription != null) {
      _encomendasRepo.client.removeChannel(_encomendasSubscription!);
    }
    _recarregador.descartar();
    _debouncePesquisa?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- CONSULTAS À BASE DE DADOS (SUPABASE) ---

  /// Dados de apoio que não dependem da lista: roteiros, motivos de paragem e
  /// técnicos. São carregados uma vez e não voltam a ser pedidos a cada evento
  /// realtime, ao contrário do que acontecia antes.
  Future<void> _carregarAuxiliares() async {
    try {
      final fasesPorProduto = await _fluxosRepo.obterFasesPorProduto();
      final reasonCodesData = await _encomendasRepo.obterReasonCodes();
      final utilizadoresData = await _utilizadoresRepo.obterParaAtribuicao();

      if (!mounted) return;
      setState(() {
        _fasesPorProduto = fasesPorProduto;
        _reasonCodes = reasonCodesData;
        _tecnicosUtilizadores = utilizadoresData;
      });
    } catch (e) {
      _mostrarMensagem('Erro ao carregar dados de apoio: ${mensagemDeErro(e)}', eErro: true);
    }
  }

  /// Carrega a primeira página, descartando o que estivesse carregado.
  ///
  /// É o que corre ao entrar no ecrã e sempre que o filtro ou a pesquisa mudam.
  Future<void> _carregarEncomendas({bool mostrarLoader = false}) async {
    if (mostrarLoader && mounted) setState(() => _isLoading = true);
    try {
      final pagina = await _encomendasRepo.obterParaPainel(
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _encomendas = pagina.itens;
        _temMais = pagina.temMais;
        _isLoading = false;
        _erroCarregamento = null;
        _erroPaginacao = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _erroCarregamento = mensagemDeErro(e);
        });
      }
    }
  }

  /// Acrescenta a página seguinte ao fim da lista.
  Future<void> _carregarMais() async {
    if (_aCarregarMais || !_temMais) return;
    setState(() {
      _aCarregarMais = true;
      _erroPaginacao = null;
    });
    try {
      final pagina = await _encomendasRepo.obterParaPainel(
        deslocamento: _encomendas.length,
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _encomendas = [..._encomendas, ...pagina.itens];
        _temMais = pagina.temMais;
        _aCarregarMais = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _aCarregarMais = false;
          _erroPaginacao = mensagemDeErro(e);
        });
      }
    }
  }

  /// Repõe exatamente as linhas que o utilizador tem carregadas, sem o levar de
  /// volta ao topo.
  ///
  /// Usado pelo realtime e depois de qualquer ação sobre uma ordem. Recarregar
  /// só a primeira página faria desaparecer tudo o que já tinha sido percorrido.
  Future<void> _recarregarMantendoPosicao() async {
    final int carregadas =
        _encomendas.length < tamanhoPaginaPadrao ? tamanhoPaginaPadrao : _encomendas.length;
    try {
      final pagina = await _encomendasRepo.obterParaPainel(
        tamanho: carregadas,
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _encomendas = pagina.itens;
        _temMais = pagina.temMais;
        _erroCarregamento = null;
      });
    } catch (e) {
      if (mounted) setState(() => _erroCarregamento = mensagemDeErro(e));
    }
  }

  /// Liga a escuta em tempo real, se o ecrã ainda cá estiver.
  ///
  /// Corre depois do primeiro carregamento, ou seja, depois de um `await`. O
  /// ecrã passou a poder ser destruído nesse intervalo — abrir o painel a
  /// partir de um KPI do dashboard recria-o com um filtro novo — e sem esta
  /// guarda ficaria um canal subscrito que já ninguém desliga, porque o
  /// `dispose` correu antes de haver canal para remover.
  void _ativarSubscricaoRealtime() {
    if (!mounted) return;
    _encomendasSubscription = _encomendasRepo.escutarProducao(
      'public:encomendas_painel',
      _aoEventoRealtime,
    );
  }

  // --- REALTIME ---

  /// Funde os eventos que não se conseguem aplicar localmente num único
  /// recarregamento. Ver [RecarregadorDebounced].
  late final RecarregadorDebounced _recarregador =
      RecarregadorDebounced(aoRecarregar: _recarregarMantendoPosicao);

  /// Decide, evento a evento, o mínimo de trabalho que repõe o ecrã correto.
  ///
  /// Antes, cada evento disparava um recarregamento da lista inteira: dez
  /// operadores a avançar fases geravam uma tempestade de pedidos. Numa fábrica
  /// com milhares de ordens, a esmagadora maioria dos eventos diz respeito a
  /// linhas que nem sequer estão à frente do utilizador — essas saem daqui sem
  /// tocar na rede. Das restantes, quase todas se resolvem com as colunas que o
  /// próprio payload traz. Só o que não se consegue resolver assim cai no
  /// recarregador com debounce.
  void _aoEventoRealtime(PostgresChangePayload evento) {
    if (!mounted) return;

    // As incidências vêm embebidas na projeção da ordem e alimentam os avisos de
    // paragem e o line clearance. O payload é da tabela `incidencias`, não da
    // ordem: não há forma de o aplicar sem reler a linha com o seu embed.
    if (evento.table != 'encomendas') {
      _recarregador.pedir();
      return;
    }

    final apagada = evento.eventType == PostgresChangeEvent.delete;
    final linha = apagada ? evento.oldRecord : evento.newRecord;
    final int? id = _inteiroDe(linha['id']);
    if (id == null) {
      // Sem chave primária não há nada a decidir (acontece se a tabela não
      // tiver REPLICA IDENTITY FULL nos DELETE).
      _recarregador.pedir();
      return;
    }

    if (apagada) {
      _removerLocalmente(id);
      return;
    }

    final indice = _encomendas.indexWhere((e) => e.id == id);
    if (indice == -1) {
      _talvezInserir(id, linha);
    } else {
      _atualizarLocalmente(indice, linha);
    }
  }

  /// Uma ordem que não está carregada só tem de entrar se pertencer a esta vista.
  void _talvezInserir(int id, Map<String, dynamic> linha) {
    if (!_pertenceAoFiltro(linha)) return;

    // A lista está ordenada por id decrescente. Uma ordem mais antiga do que a
    // última carregada vive na parte que o utilizador ainda não percorreu —
    // aparecerá sozinha quando o scroll lá chegar.
    if (_temMais && _encomendas.isNotEmpty && id < _encomendas.last.id) return;

    unawaited(_inserirDoServidor(id));
  }

  /// Vai buscar **uma** linha, com o cliente e o produto que o payload não traz.
  Future<void> _inserirDoServidor(int id) async {
    try {
      final encomenda = await _encomendasRepo.obterUmaParaPainel(id);
      if (!mounted || encomenda == null) return;
      if (_encomendas.any((e) => e.id == id)) return; // já entrou por outra via
      if (!_correspondeAPesquisa(encomenda)) return;
      setState(() {
        _encomendas = [..._encomendas, encomenda]..sort((a, b) => b.id.compareTo(a.id));
      });
    } catch (_) {
      _recarregador.pedir(); // em caso de falha, o caminho seguro
    }
  }

  /// Substitui uma linha carregada pelo que o evento diz, sem ir ao servidor.
  void _atualizarLocalmente(int indice, Map<String, dynamic> linha) {
    final atual = _encomendas[indice];

    // A precedência cancelada → em hold → concluída → em produção está toda em
    // colunas que o payload traz: dá para saber que a ordem saiu da vista.
    if (!_pertenceAoFiltro(linha)) {
      _removerLocalmente(atual.id);
      return;
    }

    final int? produtoId = _inteiroDe(linha['tipos_produtos_id']);
    final int? clienteId = _inteiroDe(linha['cliente_id']);
    final int? faseId = _inteiroDe(linha['fase_atual_id']);
    final fase = _faseDoRoteiro(produtoId, faseId);

    // Três casos em que os nomes que ficariam por atualizar vêm de junções e não
    // do payload: mudou o cliente, mudou o produto, ou a fase não existe nos
    // roteiros que temos em memória (produto novo, ou auxiliares ainda a chegar).
    if (clienteId != atual.clienteId ||
        produtoId != atual.tipoProdutoId ||
        (faseId != null && fase == null)) {
      unawaited(_substituirDoServidor(atual.id));
      return;
    }

    // Reaproveita o `fromJson` — os campos das junções são repostos a partir da
    // linha que já lá estava, que não mudou.
    final atualizada = EncomendaModel.fromJson({
      ...linha,
      'clientes': {'nome_cliente': atual.nomeCliente},
      'tipos_produto': {'nome_tipo_produto': atual.nomeProduto},
      'incidencias': atual.incidencias,
      if (fase != null)
        'fase_atual': {
          'id': fase.id,
          'nome_fase_padrao': fase.nomeFasePadrao,
          'ordem': fase.ordem,
          'posto_trabalho': fase.postoTrabalho,
          'posto_trabalho_id': fase.postoTrabalhoId,
        },
    });

    if (!_correspondeAPesquisa(atualizada)) {
      _removerLocalmente(atual.id);
      return;
    }

    setState(() {
      final lista = [..._encomendas];
      lista[indice] = atualizada;
      _encomendas = lista;
    });
  }

  /// Relê uma única linha quando o payload não chega para a reconstruir.
  Future<void> _substituirDoServidor(int id) async {
    try {
      final encomenda = await _encomendasRepo.obterUmaParaPainel(id);
      if (!mounted) return;
      final indice = _encomendas.indexWhere((e) => e.id == id);
      if (indice == -1) return;
      if (encomenda == null || !_correspondeAPesquisa(encomenda)) {
        _removerLocalmente(id);
        return;
      }
      setState(() {
        final lista = [..._encomendas];
        lista[indice] = encomenda;
        _encomendas = lista;
      });
    } catch (_) {
      _recarregador.pedir();
    }
  }

  void _removerLocalmente(int id) {
    if (!_encomendas.any((e) => e.id == id)) return;
    setState(() => _encomendas = _encomendas.where((e) => e.id != id).toList());
  }

  /// Espelho em memória do filtro que o servidor aplicou.
  ///
  /// A regra não é reescrita aqui: delega em
  /// [EncomendasRepository.pertenceAoFiltro], a mesma função de onde saem as
  /// condições SQL.
  bool _pertenceAoFiltro(Map<String, dynamic> linha) {
    return EncomendasRepository.pertenceAoFiltro(
      _filtroEstado,
      cancelada: linha['cancelada'] == true,
      emSuspenso: linha['em_suspenso'] == true,
      temFaseAtual: linha['fase_atual_id'] != null,
      dataEntrega: DateTime.tryParse(linha['data_entrega']?.toString() ?? ''),
    );
  }

  /// Espelho da pesquisa do servidor: código de rastreio ou nome de cliente.
  bool _correspondeAPesquisa(EncomendaModel e) {
    final termo = _searchController.text.trim().toLowerCase();
    if (termo.isEmpty) return true;
    return (e.codigoRastreio ?? '').toLowerCase().contains(termo) ||
        (e.nomeCliente ?? '').toLowerCase().contains(termo);
  }

  /// Resolve o nome e o posto da fase a partir dos roteiros já em memória,
  /// poupando a junção que o payload não traz.
  FaseModel? _faseDoRoteiro(int? produtoId, int? faseId) {
    if (produtoId == null || faseId == null) return null;
    for (final f in _fasesPorProduto[produtoId] ?? const <FaseModel>[]) {
      if (f.id == faseId) return f;
    }
    return null;
  }

  static int? _inteiroDe(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  void _aoEscreverPesquisa() {
    _debouncePesquisa?.cancel();
    _debouncePesquisa = Timer(esperaPesquisa, () {
      _voltarAoTopo();
      _carregarEncomendas();
    });
  }

  void _aoDeslizar() {
    if (!_scrollController.hasClients) return;
    // Depois de uma falha, o scroll deixa de pedir sozinho: senão cada gesto
    // relançaria o mesmo pedido a falhar. A retoma passa a ser do utilizador,
    // pelo botão de repetir no rodapé.
    if (_erroPaginacao != null) return;
    final posicao = _scrollController.position;
    // Antecipa o carregamento antes de se chegar ao fim, para o scroll não parar.
    if (posicao.pixels >= posicao.maxScrollExtent - 400) {
      _carregarMais();
    }
  }

  void _voltarAoTopo() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  // --- HELPER METHODS ---

  /// A regra vive em [EncomendaModel.progressoNoRoteiro]; aqui só se resolve o
  /// roteiro do produto a partir do que está carregado em memória.
  double _calcularProgresso(EncomendaModel enc) {
    final fases = _fasesPorProduto[enc.tipoProdutoId];
    return enc.progressoNoRoteiro(fases?.length ?? 0);
  }

  // --- AVANÇAR FASE ---

  /// Avança a ordem para a fase seguinte.
  ///
  /// O registo no histórico e a atualização da encomenda correm dentro de uma
  /// única transação no servidor (`avancar_fase_encomenda`). Antes eram duas
  /// escritas independentes: se a segunda falhasse, ficava histórico órfão e a
  /// ordem presa na fase anterior.
  Future<void> _avancarFase(EncomendaModel enc) async {
    try {
      final resultado = await _encomendasRepo.avancarFase(enc.id);

      final bool concluida = resultado['concluida'] == true;
      _mostrarMensagem(concluida
          ? '🏁 Ordem de produção concluída com sucesso!'
          : 'Ordem avançada para a fase: ${resultado['proxima_fase_nome'] ?? ''}!');

      _recarregarMantendoPosicao();
    } catch (e) {
      _mostrarMensagem('Erro ao avançar fase: ${mensagemDeErro(e)}', eErro: true);
    }
  }

  // --- AÇÕES DE WIP HOLD, REGISTO TÉCNICO HÍBRIDO E LINE CLEARANCE ---

  Future<void> _abrirDialogWipHold(EncomendaModel enc) async {
    final mensagem = await DialogoWipHold.mostrar(
      context,
      encomenda: enc,
      reasonCodes: _reasonCodes,
      repositorio: _encomendasRepo,
    );
    if (mensagem == null || !mounted) return;
    _mostrarMensagem(mensagem);
    _recarregarMantendoPosicao();
  }

  // --- NOVO: MODAL REGISTO TÉCNICO HÍBRIDO ---
  Future<void> _abrirDialogRegistoTecnico(
    EncomendaModel enc,
    Map<String, dynamic>? incidenciaAtiva,
  ) async {
    if (incidenciaAtiva == null) return;

    final mensagem = await DialogoRegistoTecnico.mostrar(
      context,
      incidencia: incidenciaAtiva,
      tecnicos: _tecnicosUtilizadores,
      repositorio: _encomendasRepo,
    );
    if (mensagem == null || !mounted) return;
    _mostrarMensagem(mensagem);
    _recarregarMantendoPosicao();
  }

  Future<void> _abrirDialogLineClearance(
    EncomendaModel enc,
    Map<String, dynamic>? incidenciaAtiva,
  ) async {
    final mensagem = await DialogoLineClearance.mostrar(
      context,
      incidencia: incidenciaAtiva,
      repositorio: _encomendasRepo,
    );
    if (mensagem == null || !mounted) return;
    _mostrarMensagem(mensagem);
    _recarregarMantendoPosicao();
  }

  Future<void> _abrirDialogHistorico(EncomendaModel enc) {
    return DialogoHistoricoOrdem.mostrar(
      context,
      encomenda: enc,
      repositorio: _encomendasRepo,
    );
  }

  /// Cancela a ordem preservando todo o histórico de produção e incidências.
  ///
  /// Antes fazia-se `DELETE`, o que destruía a rastreabilidade da ordem — algo
  /// inaceitável num contexto fabril. Agora a ordem fica marcada como cancelada,
  /// com motivo, autor e data.
  Future<void> _cancelarOrdem(int id, String motivo) async {
    try {
      setState(() => _isLoading = true);
      await _encomendasRepo.cancelar(encomendaId: id, motivo: motivo);
      _mostrarMensagem('Ordem cancelada. O histórico foi preservado para auditoria.');
      await _recarregarMantendoPosicao();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      _mostrarMensagem('Erro ao cancelar ordem: ${mensagemDeErro(e)}', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarEdicaoOrdem(int id, String novaData, int? novaFaseId) async {
    try {
      setState(() => _isLoading = true);

      await _encomendasRepo.atualizar(
        id: id,
        dataEntrega: novaData,
        faseAtualId: novaFaseId,
      );
      _mostrarMensagem('Ordem atualizada com sucesso!');
      await _recarregarMantendoPosicao();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      _mostrarMensagem('Erro ao editar ordem: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarMensagem(String msg, {bool eErro = false}) {
    if (mounted) {
      context.mostrarMensagem(msg, eErro: eErro);
    }
  }

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
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
                        'Ordens de Produção em Curso',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                      ),
                      const SizedBox(height: 20),

                      // PESQUISA E FILTROS DE ESTADO (FIXOS NO TOPO)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Pesquisar por Código de Rastreio ou Cliente...',
                                prefixIcon: const Icon(Icons.search, color: TemasCores.textoTerciario, size: 20),
                                fillColor: TemasCores.superficieSuave,
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<FiltroEstadoOrdem>(
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: FiltroEstadoOrdem.todos,
                                label: Text('Todas', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: FiltroEstadoOrdem.emProducao,
                                label: Text('Em Produção', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.circle, color: TemasCores.sucesso, size: 8),
                              ),
                              ButtonSegment(
                                value: FiltroEstadoOrdem.emHold,
                                label: Text('ON HOLD', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.circle, color: TemasCores.erro, size: 8),
                              ),
                              ButtonSegment(
                                value: FiltroEstadoOrdem.atrasada,
                                label: Text('Atrasadas', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.warning_amber_rounded, size: 14),
                              ),
                              ButtonSegment(
                                value: FiltroEstadoOrdem.concluida,
                                label: Text('Concluídas', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.flag_rounded, size: 14),
                              ),
                              ButtonSegment(
                                value: FiltroEstadoOrdem.cancelada,
                                label: Text('Canceladas', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.block_rounded, size: 14),
                              ),
                            ],
                            selected: {_filtroEstado},
                            onSelectionChanged: (set) {
                              setState(() => _filtroEstado = set.first);
                              // Mudar de filtro recomeça a paginação do início.
                              _voltarAoTopo();
                              _carregarEncomendas();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // A atualização falhou mas há linhas no ecrã: elas ficam,
                      // devidamente marcadas como podendo já não refletir a
                      // fábrica.
                      if (_erroCarregamento != null && _encomendas.isNotEmpty)
                        EstadoErro.compacto(
                          titulo: 'A lista pode estar desatualizada — falhou a última atualização.',
                          detalhe: _erroCarregamento,
                          aoRepetir: _recarregarMantendoPosicao,
                        ),

                      // LISTA DE ORDENS COM SCROLL INTERNO RESTRITO
                      Expanded(
                        child: _encomendas.isEmpty
                            // Lista vazia por falha é uma coisa; lista vazia
                            // porque não há ordens é outra. Antes eram o mesmo
                            // ecrã.
                            ? (_erroCarregamento != null
                                ? EstadoErro(
                                    titulo: 'Não foi possível carregar as ordens de produção',
                                    detalhe: _erroCarregamento,
                                    aoRepetir: () => _carregarEncomendas(mostrarLoader: true),
                                  )
                                : const Center(
                                    child: Text(
                                      'Não existem ordens de produção ativas correspondentes à pesquisa.',
                                      style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
                                    ),
                                  ))
                            : ListView.builder(
                                controller: _scrollController,
                                // A última posição é o rodapé de paginação, não uma ordem.
                                itemCount: _encomendas.length + (_temMais ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _encomendas.length) {
                                    return RodapePaginacao(
                                      aCarregar: _aCarregarMais,
                                      erro: _erroPaginacao,
                                      aoCarregarMais: _carregarMais,
                                      tituloErro: 'Não foi possível carregar mais ordens.',
                                    );
                                  }
                                  final enc = _encomendas[index];
                                  return CartaoOrdemProducao(
                                    encomenda: enc,
                                    progresso: _calcularProgresso(enc),
                                    aoAvancarFase: () => _avancarFase(enc),
                                    aoWipHold: () => _abrirDialogWipHold(enc),
                                    aoRegistoTecnico: (incidencia) =>
                                        _abrirDialogRegistoTecnico(enc, incidencia),
                                    aoLineClearance: (incidencia) =>
                                        _abrirDialogLineClearance(enc, incidencia),
                                    aoHistorico: () => _abrirDialogHistorico(enc),
                                    aoEditar: () => _abrirDialogEditar(enc),
                                    aoCancelar: (idFormatado) =>
                                        _confirmarCancelamento(enc.id, idFormatado),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // --- POPUPS E DIALOGS ADICIONAIS ---

  Future<void> _confirmarCancelamento(int id, String refOrdem) async {
    final motivo = await DialogoCancelarOrdem.mostrar(
      context,
      referencia: refOrdem,
    );
    if (motivo == null || !mounted) return;
    await _cancelarOrdem(id, motivo);
  }

  Future<void> _abrirDialogEditar(EncomendaModel enc) async {
    final edicao = await DialogoEditarOrdem.mostrar(
      context,
      encomenda: enc,
      fases: _fasesPorProduto[enc.tipoProdutoId] ?? const <FaseModel>[],
    );
    if (edicao == null || !mounted) return;
    await _salvarEdicaoOrdem(enc.id, edicao.dataEntrega, edicao.faseAtualId);
  }
}
