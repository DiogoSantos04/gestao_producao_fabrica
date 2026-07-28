import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, PostgresChangePayload, RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/paginacao.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import 'widgets/etiqueta_estado.dart';
import '../../core/formatos.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../models/fase_model.dart';
import '../../models/historico_model.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/utilizadores_repository.dart';

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({super.key});

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
  List<Map<String, dynamic>> _reasonCodes = [];
  List<Map<String, dynamic>> _tecnicosUtilizadores = []; // Lista de técnicos/utilizadores da empresa
  Map<int, List<FaseModel>> _fasesPorProduto = {};

  FiltroEstadoOrdem _filtroEstado = FiltroEstadoOrdem.todos;
  bool _isLoading = true;
  bool _aCarregarMais = false;
  bool _temMais = false;

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
      _mostrarMensagem('Erro ao carregar dados de apoio: ${_limparErro(e)}', eErro: true);
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
      });
    } catch (e) {
      _mostrarMensagem('Erro ao carregar ordens: ${_limparErro(e)}', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Acrescenta a página seguinte ao fim da lista.
  Future<void> _carregarMais() async {
    if (_aCarregarMais || !_temMais) return;
    setState(() => _aCarregarMais = true);
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
      _mostrarMensagem('Erro ao carregar mais ordens: ${_limparErro(e)}', eErro: true);
      if (mounted) setState(() => _aCarregarMais = false);
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
      });
    } catch (e) {
      _mostrarMensagem('Erro ao atualizar ordens: ${_limparErro(e)}', eErro: true);
    }
  }

  void _ativarSubscricaoRealtime() {
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

  /// Espelho em memória de `EncomendasRepository._aplicarFiltroEstado`.
  ///
  /// A regra em si não é reescrita aqui: deriva-se o estado com
  /// [EstadoOrdem.derivar] — a mesma função que o repositório traduziu para SQL —
  /// e compara-se com [FiltroEstadoOrdem.estado].
  bool _pertenceAoFiltro(Map<String, dynamic> linha) {
    final cancelada = linha['cancelada'] == true;
    final alvo = _filtroEstado.estado;
    // "Todas" exclui as canceladas, que só aparecem no seu próprio filtro.
    if (alvo == null) return !cancelada;
    return alvo ==
        EstadoOrdem.derivar(
          cancelada: cancelada,
          emSuspenso: linha['em_suspenso'] == true,
          temFaseAtual: linha['fase_atual_id'] != null,
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

  double _calcularProgresso(EncomendaModel enc) {
    if (enc.faseAtualId == null) return 1.0;

    final prodId = enc.tipoProdutoId;
    final ordemAtual = enc.ordemFaseAtual;
    if (prodId == null || ordemAtual == null) return 0.0;

    final fases = _fasesPorProduto[prodId];
    if (fases == null || fases.isEmpty) return 0.0;

    return ((ordemAtual - 1) / fases.length).clamp(0.0, 1.0);
  }

  bool _verificarSeAtrasada(DateTime? dataEntrega) {
    if (dataEntrega == null) return false;
    final hoje = DateTime.now();
    final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
    return hojeSemHoras.isAfter(dataEntrega);
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
      _mostrarMensagem('Erro ao avançar fase: ${_limparErro(e)}', eErro: true);
    }
  }

  /// Os repositórios já devolvem mensagens de negócio legíveis; aqui só removemos
  /// o prefixo das exceções genéricas.
  String _limparErro(Object e) {
    if (e is RepositoryException) return e.mensagem;
    return e.toString().replaceAll('Exception: ', '');
  }

  // --- AÇÕES DE WIP HOLD, REGISTO TÉCNICO HÍBRIDO E LINE CLEARANCE ---

  void _abrirDialogWipHold(EncomendaModel enc) {
    int? selectedReasonId;
    final notasController = TextEditingController();
    bool isSubmitting = false;

    final Map<int, Map<String, dynamic>> reasonCodesMap = {};
    for (var r in _reasonCodes) {
      final int rId = int.parse(r['id'].toString());
      reasonCodesMap[rId] = Map<String, dynamic>.from(r);
    }
    final listaReasonCodesUnicos = reasonCodesMap.values.toList();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.pause_circle_filled_rounded, color: TemasCores.erroTexto),
                  const SizedBox(width: 8),
                  const Text('Suspender Ordem (WIP Hold)'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione o motivo oficial (Reason Code) da paragem na linha:',
                      style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedReasonId,
                      decoration: const InputDecoration(
                        labelText: 'Reason Code *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: listaReasonCodesUnicos.map((r) {
                        final int rId = int.parse(r['id'].toString());
                        final cat = r['categoria'] ?? 'Geral';
                        final desc = r['descricao'] ?? '';
                        return DropdownMenuItem<int>(
                          value: rId,
                          child: Text('[$cat] $desc', style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: isSubmitting
                          ? null
                          : (val) => setDialogState(() => selectedReasonId = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notasController,
                      enabled: !isSubmitting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descrição / Observações do Operador',
                        hintText: 'Ex: Frequência de ruído anormal no equipamento.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          notasController.dispose();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemasCores.erroTexto,
                    foregroundColor: TemasCores.textoInverso,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: TemasCores.textoInverso, strokeWidth: 2),
                        )
                      : const Icon(Icons.block, size: 16),
                  label: const Text('Aplicar WIP Hold'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (selectedReasonId == null) {
                            _mostrarMensagem('Selecione um motivo de paragem.', eErro: true);
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          try {
                            final int encId = enc.id;

                            // Criar a incidência e suspender a ordem é uma só
                            // transação — e o posto de trabalho é resolvido no
                            // servidor a partir da fase atual.
                            await _encomendasRepo.aplicarWipHold(
                              encomendaId: encId,
                              reasonCodeId: selectedReasonId!,
                              descricaoOperador: notasController.text.trim(),
                            );

                            notasController.dispose();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🔴 Ordem colocada em ON HOLD!');
                            _recarregarMantendoPosicao();
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aplicar WIP Hold: ${_limparErro(e)}', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- NOVO: MODAL REGISTO TÉCNICO HÍBRIDO ---
  void _abrirDialogRegistoTecnico(EncomendaModel enc, Map<String, dynamic>? incidenciaAtiva) {
    if (incidenciaAtiva == null) return;

    String tipoManutencao = 'INTERNA'; // 'INTERNA' ou 'EXTERNA'
    String? tecnicoSelecionadoId;
    final entidadeExternaController = TextEditingController();
    final notaTecnicaController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.build_circle_rounded, color: TemasCores.avisoTextoForte),
                  const SizedBox(width: 8),
                  const Text('Registo Técnico de Intervenção'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: TemasCores.avisoFundo,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: TemasCores.avisoBorda),
                      ),
                      child: Text(
                        'Incidente: ${incidenciaAtiva['motivo'] ?? 'Manutenção Requerida'}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.avisoTextoForte),
                      ),
                    ),

                    const Text('Tipo de Intervenção Técnica:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'INTERNA',
                          label: Text('Manutenção Interna'),
                          icon: Icon(Icons.engineering_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: 'EXTERNA',
                          label: Text('Assistência Externa'),
                          icon: Icon(Icons.fire_truck_rounded, size: 16),
                        ),
                      ],
                      selected: {tipoManutencao},
                      onSelectionChanged: isSubmitting
                          ? null
                          : (newSelection) {
                              setDialogState(() {
                                tipoManutencao = newSelection.first;
                              });
                            },
                    ),
                    const SizedBox(height: 16),

                    if (tipoManutencao == 'INTERNA') ...[
                      DropdownButtonFormField<String>(
                        value: tecnicoSelecionadoId,
                        decoration: const InputDecoration(
                          labelText: 'Técnico Responsável *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _tecnicosUtilizadores.map((u) {
                          final id = u['utilizador_id'].toString();
                          final nome = u['nome_utilizador'] ?? 'Sem nome';
                          final perfil = u['perfil'] ?? 'Utilizador';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text('$nome ($perfil)', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: isSubmitting
                            ? null
                            : (val) => setDialogState(() => tecnicoSelecionadoId = val),
                      ),
                    ] else ...[
                      TextField(
                        controller: entidadeExternaController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Empresa / Entidade Externa *',
                          hintText: 'Ex: Siemens, Kuka Robotics, EletroCaldas',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    TextField(
                      controller: notaTecnicaController,
                      enabled: !isSubmitting,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Relatório Técnico / Ações Corretivas',
                        hintText: 'Descreva os trabalhos efetuados, peças substituídas ou calibração efetuada...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          entidadeExternaController.dispose();
                          notaTecnicaController.dispose();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemasCores.avisoTexto,
                    foregroundColor: TemasCores.textoInverso,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: TemasCores.textoInverso, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Concluir Intervenção Técnica'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (tipoManutencao == 'INTERNA' && tecnicoSelecionadoId == null) {
                            _mostrarMensagem('Selecione o técnico interno responsável.', eErro: true);
                            return;
                          }
                          if (tipoManutencao == 'EXTERNA' && entidadeExternaController.text.trim().isEmpty) {
                            _mostrarMensagem('Indique a empresa de assistência externa.', eErro: true);
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          try {
                            final int incId = int.parse(incidenciaAtiva['id'].toString());

                            await _encomendasRepo.registarIntervencaoTecnica(
                              incidenciaId: incId,
                              tipoManutencao: tipoManutencao,
                              tecnicoId: tipoManutencao == 'INTERNA' ? tecnicoSelecionadoId : null,
                              entidadeExterna: tipoManutencao == 'EXTERNA'
                                  ? entidadeExternaController.text.trim()
                                  : null,
                              notaTecnica: notaTecnicaController.text.trim(),
                            );

                            entidadeExternaController.dispose();
                            notaTecnicaController.dispose();

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🛠️ Registo técnico concluído! A ordem aguarda agora Line Clearance.');
                            _recarregarMantendoPosicao();
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao gravar registo técnico: $e', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirDialogLineClearance(EncomendaModel enc, Map<String, dynamic>? incidenciaAtiva) {
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: TemasCores.sucessoTexto),
                  const SizedBox(width: 8),
                  const Text('Aprovar Line Clearance (FAI)'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (incidenciaAtiva != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: TemasCores.sucessoFundo,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: TemasCores.sucessoBorda),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resumo da Intervenção Técnica:',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: TemasCores.sucessoTextoIntenso),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tipo: ${incidenciaAtiva['tipo_manutencao'] ?? 'N/A'}',
                              style: const TextStyle(fontSize: 12, color: TemasCores.sucessoTextoIntenso),
                            ),
                            if (incidenciaAtiva['tipo_manutencao'] == 'INTERNA')
                              Text(
                                'Técnico: ${incidenciaAtiva['utilizadores']?['nome_utilizador'] ?? 'Técnico Interno'}',
                                style: const TextStyle(fontSize: 12, color: TemasCores.sucessoTextoIntenso),
                              )
                            else if (incidenciaAtiva['tipo_manutencao'] == 'EXTERNA')
                              Text(
                                'Entidade: ${incidenciaAtiva['entidade_externa'] ?? 'Empresa Externa'}',
                                style: const TextStyle(fontSize: 12, color: TemasCores.sucessoTextoIntenso),
                              ),
                            if (incidenciaAtiva['nota_tecnica'] != null &&
                                incidenciaAtiva['nota_tecnica'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Nota Técnica: ${incidenciaAtiva['nota_tecnica']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: TemasCores.sucessoTextoForte,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Text('Confirmação de Qualidade:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      'Ao aprovar o Line Clearance, confirma que a 1ª peça (First Article Inspection) foi validada e a linha de produção está limpa e pronta a retomar.',
                      style: const TextStyle(fontSize: 11, color: TemasCores.textoApoioForte),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemasCores.sucessoTexto,
                    foregroundColor: TemasCores.textoInverso,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: TemasCores.textoInverso, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Validar & Libertar Linha'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);

                          try {
                            if (incidenciaAtiva == null) {
                              throw Exception('Não há incidência ativa para validar.');
                            }

                            // Fechar a incidência e libertar a ordem numa só transação.
                            await _encomendasRepo.aprovarLineClearance(
                              int.parse(incidenciaAtiva['id'].toString()),
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🟢 Line Clearance Aprovado! Produção retomada.');
                            _recarregarMantendoPosicao();
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aprovar Line Clearance: ${_limparErro(e)}', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- HISTÓRICO & TIMELINE DE RASTREABILIDADE ---

  /// Converte a rastreabilidade da ordem numa lista de eventos ordenada do mais
  /// recente para o mais antigo.
  ///
  /// Cada incidência pode gerar até três eventos: o WIP Hold, a reparação técnica
  /// e o line clearance.
  List<Map<String, dynamic>> _construirEventosTimeline(TimelineOrdem? timeline) {
    final eventos = <Map<String, dynamic>>[];

    for (final p in timeline?.producao ?? const <HistoricoModel>[]) {
      final data = p.momento;
      eventos.add({
        'timestamp': data ?? DateTime.now(),
        'data_str': data?.toIso8601String() ?? '',
        'titulo': 'Concluída Fase ${p.ordemFase ?? ''}: ${p.nomeFase ?? 'Fase de Produção'}',
        'subtitulo': 'Executado por: ${p.nomeUtilizador ?? 'Operador'}',
        'tipo': 'PRODUCAO',
        'cor': TemasCores.sucessoTexto,
        'icone': Icons.check_circle_rounded,
      });
    }

    for (final inc in timeline?.incidencias ?? const <IncidenciaModel>[]) {
      final dataRegisto = inc.inicio;
      final motivo = inc.motivo ?? 'Incidente em Linha';
      final notaOp = inc.descricaoOperador;

      eventos.add({
        'timestamp': dataRegisto ?? DateTime.now(),
        'data_str': dataRegisto?.toIso8601String() ?? '',
        'titulo': 'WIP Hold (Linha Suspensa)',
        'subtitulo': 'Motivo: $motivo${notaOp != null && notaOp.isNotEmpty ? "\nNota: $notaOp" : ""}',
        'tipo': 'HOLD',
        'cor': TemasCores.erroTexto,
        'icone': Icons.pause_circle_filled_rounded,
      });

      if (inc.manutencaoConcluida) {
        final dataManut = inc.dataFimManutencao ?? dataRegisto;
        final notaTec = inc.notaTecnica ?? '';
        eventos.add({
          'timestamp': dataManut ?? DateTime.now(),
          'data_str': dataManut?.toIso8601String() ?? '',
          'titulo': 'Reparação Técnica Concluída (${inc.tipoManutencao ?? 'N/A'})',
          'subtitulo':
              'Responsável: ${inc.responsavelIntervencao ?? 'Técnico'}${notaTec.isNotEmpty ? "\nRelatório: $notaTec" : ""}',
          'tipo': 'MANUTENCAO',
          'cor': TemasCores.avisoTextoForte,
          'icone': Icons.build_circle_rounded,
        });
      }

      if (inc.lineClearanceValidado && inc.dataLineClearance != null) {
        final dataClearance = inc.dataLineClearance!;
        eventos.add({
          'timestamp': dataClearance,
          'data_str': dataClearance.toIso8601String(),
          'titulo': 'Line Clearance Aprovado (Produção Retomada)',
          'subtitulo': 'Aprovado por Responsável de Qualidade/Supervisão',
          'tipo': 'CLEARANCE',
          'cor': TemasCores.infoTextoForte,
          'icone': Icons.verified_user_rounded,
        });
      }
    }

    return eventos;
  }

  Future<void> _abrirDialogHistorico(EncomendaModel enc) async {
    final int encId = enc.id;
    final idFormatado = Formatos.referenciaOrdem(
      encId,
      criadaEm: enc.createdAt?.toIso8601String(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: TemasCores.marcaEscura),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Histórico & Rastreabilidade - $idFormatado',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            height: 450,
            child: FutureBuilder(
              future: _encomendasRepo.obterTimeline(encId),
              builder: (context, AsyncSnapshot<TimelineOrdem> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar histórico: ${snapshot.error}', style: const TextStyle(color: TemasCores.erro)),
                  );
                }

                final eventosTimeline = _construirEventosTimeline(snapshot.data);

                if (eventosTimeline.isEmpty) {
                  return const Center(
                    child: Text('Nenhum evento registado no histórico desta ordem.', style: TextStyle(color: TemasCores.textoTerciario)),
                  );
                }

                eventosTimeline.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

                return ListView.builder(
                  itemCount: eventosTimeline.length,
                  itemBuilder: (context, idx) {
                    final item = eventosTimeline[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: (item['cor'] as Color).withOpacity(0.15),
                                child: Icon(item['icone'] as IconData, size: 16, color: item['cor'] as Color),
                              ),
                              if (idx != eventosTimeline.length - 1)
                                Container(
                                  width: 2,
                                  height: 35,
                                  color: TemasCores.bordaForte,
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: TemasCores.superficieTenue,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: TemasCores.borda),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['titulo'].toString(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: item['cor'] as Color,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        Formatos.dataHora(item['data_str']),
                                        style: const TextStyle(fontSize: 10, color: TemasCores.textoTerciario),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['subtitulo'].toString(),
                                    style: const TextStyle(fontSize: 11, color: TemasCores.textoApoioIntenso),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
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
      _mostrarMensagem('Erro ao cancelar ordem: ${_limparErro(e)}', eErro: true);
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

                      // LISTA DE ORDENS COM SCROLL INTERNO RESTRITO
                      Expanded(
                        child: _encomendas.isEmpty
                            ? const Center(
                                child: Text(
                                  'Não existem ordens de produção ativas correspondentes à pesquisa.',
                                  style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                // A última posição é o rodapé de paginação, não uma ordem.
                                itemCount: _encomendas.length + (_temMais ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _encomendas.length) {
                                    return _buildRodapePaginacao();
                                  }
                                  return _buildOrdemCard(_encomendas[index]);
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

  /// Rodapé da lista paginada.
  ///
  /// O scroll já dispara o carregamento sozinho ao aproximar-se do fim; o botão
  /// existe como saída manual para o caso de a janela ser alta o suficiente para
  /// a página caber sem haver scroll nenhum.
  Widget _buildRodapePaginacao() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _aCarregarMais
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: _carregarMais,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Carregar mais', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }

  /// Cores do badge de estado, derivadas de [EstadoOrdem].
  ({Color fundo, Color borda, Color texto}) _coresEstado(EstadoOrdem estado) {
    return switch (estado) {
      EstadoOrdem.cancelada => (
          fundo: TemasCores.superficieInerte,
          borda: TemasCores.bordaNeutra,
          texto: TemasCores.inativoTexto
        ),
      EstadoOrdem.emHold => (
          fundo: TemasCores.erroFundo,
          borda: TemasCores.erroClaro,
          texto: TemasCores.erroTextoForte
        ),
      EstadoOrdem.concluida => (
          fundo: TemasCores.sucessoFundo,
          borda: TemasCores.sucessoClaro,
          texto: TemasCores.sucessoTextoForte
        ),
      EstadoOrdem.emProducao => (
          fundo: TemasCores.infoFundo,
          borda: TemasCores.infoClaro,
          texto: TemasCores.infoTextoForte
        ),
    };
  }

  /// Linha de etiquetas do cartão: referência, código de rastreio, estado,
  /// atraso e prioridade.
  Widget _buildLinhaEtiquetas({
    required String idFormatado,
    required String codigoRastreio,
    required EstadoOrdem estado,
    required bool atrasada,
    required String prioridade,
  }) {
    final cores = _coresEstado(estado);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          idFormatado,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: TemasCores.textoPrimario),
        ),
        _etiqueta(codigoRastreio,
            fundo: TemasCores.superficieSuave, texto: TemasCores.textoApoioForte, paddingHorizontal: 6),
        EtiquetaEstado.compacta(
          rotulo: estado.etiqueta,
          fundo: cores.fundo,
          texto: cores.texto,
          borda: cores.borda,
        ),
        if (atrasada)
          _etiqueta('Atrasada', fundo: TemasCores.erroFundo, texto: TemasCores.erroTexto),
        if (prioridade != 'Normal')
          _etiqueta(prioridade.toUpperCase(),
              fundo: TemasCores.alertaFundo, texto: TemasCores.alertaTextoForte),
      ],
    );
  }

  /// Etiqueta simples com fundo colorido.
  Widget _etiqueta(
    String rotulo, {
    required Color fundo,
    required Color texto,
    double paddingHorizontal = 8,
  }) {
    return EtiquetaEstado.compacta(
      rotulo: rotulo,
      fundo: fundo,
      texto: texto,
      paddingHorizontal: paddingHorizontal,
    );
  }

  /// Botões de ação do cartão, condicionados ao estado da ordem.
  ///
  /// Regras preservadas do original: uma ordem **cancelada** só permite consultar
  /// o histórico; em **hold** mostra Registo Técnico ou Line Clearance conforme a
  /// manutenção já esteja registada; **em produção** mostra WIP Hold e Avançar Fase;
  /// **concluída** mostra apenas Histórico, Editar e Cancelar.
  Widget _buildBotoesAcao({
    required EncomendaModel enc,
    required EstadoOrdem estado,
    required String idFormatado,
    required Map<String, dynamic>? incidenciaAtiva,
    required bool manutencaoConcluida,
  }) {
    final cancelada = estado == EstadoOrdem.cancelada;
    final emHold = estado == EstadoOrdem.emHold;
    final concluida = estado == EstadoOrdem.concluida;

    const paddingBotao = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    final contornoNeutro = OutlinedButton.styleFrom(
      side: const BorderSide(color: TemasCores.bordaForte),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: paddingBotao,
    );

    return Row(
      children: [
        if (!cancelada && emHold) ...[
          if (!manutencaoConcluida)
            ElevatedButton.icon(
              onPressed: () => _abrirDialogRegistoTecnico(enc, incidenciaAtiva),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.avisoTexto,
                foregroundColor: TemasCores.textoInverso,
                padding: paddingBotao,
              ),
              icon: const Icon(Icons.build_rounded, size: 14),
              label: const Text('Registo Técnico', style: TextStyle(fontSize: 12)),
            )
          else
            ElevatedButton.icon(
              onPressed: () => _abrirDialogLineClearance(enc, incidenciaAtiva),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.sucessoTexto,
                foregroundColor: TemasCores.textoInverso,
                padding: paddingBotao,
              ),
              icon: const Icon(Icons.verified_user_rounded, size: 14),
              label: const Text('Line Clearance', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(width: 8),
        ] else if (!cancelada && !concluida) ...[
          OutlinedButton.icon(
            onPressed: () => _abrirDialogWipHold(enc),
            style: OutlinedButton.styleFrom(
              foregroundColor: TemasCores.erroTexto,
              side: const BorderSide(color: TemasCores.erroClaro),
              padding: paddingBotao,
            ),
            icon: const Icon(Icons.pause, size: 14),
            label: const Text('WIP Hold', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _avancarFase(enc),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.marcaEscura,
              foregroundColor: TemasCores.textoInverso,
              padding: paddingBotao,
            ),
            icon: const Icon(Icons.skip_next_rounded, size: 14),
            label: const Text('Avançar Fase', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],

        OutlinedButton.icon(
          onPressed: () => _abrirDialogHistorico(enc),
          style: contornoNeutro,
          icon: const Icon(Icons.history_rounded, size: 14, color: TemasCores.acentoAzulAcinzentado),
          label: const Text('Histórico', style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12)),
        ),
        const SizedBox(width: 8),

        if (!cancelada) ...[
          OutlinedButton.icon(
            onPressed: () => _abrirDialogEditar(enc),
            style: contornoNeutro,
            icon: const Icon(Icons.edit_outlined, size: 14, color: TemasCores.textoPrimario),
            label: const Text('Editar', style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12)),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmarCancelamento(enc.id, idFormatado),
            style: contornoNeutro,
            icon: const Icon(Icons.cancel_outlined, size: 14, color: TemasCores.textoPrimario),
            label: const Text('Cancelar', style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12)),
          ),
        ],
      ],
    );
  }

  Widget _buildOrdemCard(EncomendaModel enc) {
    final idFormatado = Formatos.referenciaOrdem(
      enc.id,
      criadaEm: enc.createdAt?.toIso8601String(),
    );
    final String codigoRastreio = enc.codigoRastreio ?? 'N/A';
    final String nomeCliente = enc.nomeCliente ?? 'N/A';
    final String nomeProduto = enc.nomeProduto ?? 'N/A';
    final String prioridade = enc.prioridade;

    final estado = enc.estado;
    final bool cancelada = estado == EstadoOrdem.cancelada;
    final bool emHold = estado == EstadoOrdem.emHold;
    final bool concluida = estado == EstadoOrdem.concluida;

    final String faseNome = concluida
        ? 'Produção Concluída'
        : (enc.nomeFaseAtual != null
            ? 'Fase ${enc.ordemFaseAtual}: ${enc.nomeFaseAtual}'
            : 'Aguardando Início');
    final String postoTrabalho = enc.postoFaseAtual ?? 'Linha Geral';
    final String dataEntrega = enc.dataEntregaIso ?? '';

    final double progresso = _calcularProgresso(enc);
    final int progressoPercentagem = (progresso * 100).toInt();
    final bool atrasada = _verificarSeAtrasada(enc.dataEntrega);

    // Incidência ativa: o modelo aplica a regra (sem line clearance validado)
    final Map<String, dynamic>? incidenciaAtiva = enc.incidenciaAtiva;
    final bool manutencaoConcluida = incidenciaAtiva?['manutencao_concluida'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: emHold ? TemasCores.erroClaro : TemasCores.borda, width: emHold ? 2 : 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLinhaEtiquetas(
                        idFormatado: idFormatado,
                        codigoRastreio: codigoRastreio,
                        estado: estado,
                        atrasada: atrasada,
                        prioridade: prioridade,
                      ),
                      const SizedBox(height: 8),
                      Text(nomeCliente, style: const TextStyle(color: TemasCores.textoApoioForte, fontSize: 13)),
                      Text(nomeProduto, style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 12)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text('Fase Atual: ', style: const TextStyle(fontSize: 13, color: TemasCores.textoApoio)),
                          Text(faseNome,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
                          if (!concluida) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(postoTrabalho, style: const TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: TemasCores.textoTerciario),
                        const SizedBox(width: 6),
                        Text(
                          dataEntrega,
                          style: TextStyle(
                              fontSize: 12, color: TemasCores.textoApoio, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildBotoesAcao(
                      enc: enc,
                      estado: estado,
                      idFormatado: idFormatado,
                      incidenciaAtiva: incidenciaAtiva,
                      manutencaoConcluida: manutencaoConcluida,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$progressoPercentagem% concluído',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.textoApoio),
                    )
                  ],
                ),
              ],
            ),
          ),

          // MOTIVO DO CANCELAMENTO (rasto de auditoria)
          if (cancelada) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: TemasCores.superficieSuave,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TemasCores.bordaForte),
              ),
              child: Row(
                children: [
                  Icon(Icons.block_rounded, color: TemasCores.textoApoioForte, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ORDEM CANCELADA em ${Formatos.dataHora(enc.dataCancelamento?.toIso8601String())} — '
                      '${enc.motivoCancelamento ?? 'sem motivo registado'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.textoApoioIntenso),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // BANNER ALERTA DE INCIDÊNCIA ATIVA / ESTADO DA REPARAÇÃO
          if (emHold && incidenciaAtiva != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: manutencaoConcluida ? TemasCores.sucessoFundo : TemasCores.avisoFundo,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: manutencaoConcluida ? TemasCores.sucessoClaro : TemasCores.avisoBorda),
              ),
              child: Row(
                children: [
                  Icon(
                    manutencaoConcluida ? Icons.build_circle_rounded : Icons.warning_rounded,
                    color: manutencaoConcluida ? TemasCores.sucessoTextoForte : TemasCores.avisoTextoForte,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manutencaoConcluida
                              ? 'REPARAÇÃO TÉCNICA CONCLUÍDA — AGUARDA LINE CLEARANCE (QUALIDADE)'
                              : 'BLOQUEIO EM LINHA: ${incidenciaAtiva['motivo'] ?? 'Manutenção Pendente'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: manutencaoConcluida ? TemasCores.sucessoTextoIntenso : TemasCores.avisoTextoForte,
                          ),
                        ),
                        if (incidenciaAtiva['descricao_operador'] != null &&
                            incidenciaAtiva['descricao_operador'].toString().isNotEmpty)
                          Text(
                            'Nota Operador: ${incidenciaAtiva['descricao_operador']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: manutencaoConcluida ? TemasCores.sucessoTextoForte : TemasCores.avisoTexto,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: TemasCores.superficieSuave,
              valueColor: AlwaysStoppedAnimation<Color>(
                emHold ? TemasCores.erro : (concluida ? TemasCores.sucesso : TemasCores.marcaEscura),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- POPUPS E DIALOGS ADICIONAIS ---

  void _confirmarCancelamento(int id, String refOrdem) {
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cancelar Ordem de Produção'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A ordem $refOrdem será marcada como cancelada. O histórico de '
                      'produção e as incidências são preservados para auditoria.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: motivoController,
                      maxLines: 2,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Motivo do cancelamento *',
                        hintText: 'Ex: Anulação a pedido do cliente.',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    motivoController.dispose();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Não'),
                ),
                ElevatedButton(
                  onPressed: motivoController.text.trim().isEmpty
                      ? null
                      : () {
                          final motivo = motivoController.text.trim();
                          motivoController.dispose();
                          Navigator.pop(dialogContext);
                          _cancelarOrdem(id, motivo);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: TemasCores.erro, foregroundColor: TemasCores.textoInverso),
                  child: const Text('Sim, Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirDialogEditar(EncomendaModel enc) {
    final dataController = TextEditingController(text: enc.dataEntregaIso ?? '');
    final fasesDisponiveis = List<FaseModel>.from(
      _fasesPorProduto[enc.tipoProdutoId] ?? const <FaseModel>[],
    );

    int? faseIdSelecionada = enc.faseAtualId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Ordem de Produção'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dataController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Data de Entrega (AAAA-MM-DD)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final DateTime? data = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(dataController.text) ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (data != null) {
                        setDialogState(() {
                          dataController.text =
                              "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: faseIdSelecionada,
                    decoration: const InputDecoration(labelText: 'Fase Atual de Produção'),
                    items: [
                      ...fasesDisponiveis.map((f) {
                        return DropdownMenuItem<int?>(
                          value: f.id,
                          child: Text('Fase ${f.ordem}: ${f.nomeFasePadrao}'),
                        );
                      }),
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('🏁 Dar como Concluída'),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => faseIdSelecionada = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dataController.dispose();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final novaData = dataController.text.trim();
                    dataController.dispose();
                    Navigator.pop(dialogContext);
                    _salvarEdicaoOrdem(
                      enc.id,
                      novaData,
                      faseIdSelecionada,
                    );
                  },
                  child: const Text('Gravar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}