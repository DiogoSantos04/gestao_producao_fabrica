import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/breakpoints.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/postos_repository.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/cartao_kpi.dart';

/// Descreve, em texto, como o valor de hoje se compara com o de ontem.
///
/// Fica no subtítulo do KPI em vez de num segundo número: o cartão tem uma
/// linha só e "+2 vs ontem" diz mais do que um "2" ao lado de um "4" sem
/// contexto. A percentagem é omitida de propósito — com totais de um dígito,
/// uma ordem a mais dava "+100%" e parecia um salto de produtividade.
String descreverVariacaoDiaria(int hoje, int ontem) {
  final diferenca = hoje - ontem;
  if (diferenca == 0) {
    // Zero e zero não é "estável": é uma linha que não produziu nada em dois
    // dias, e dizer "igual a ontem" mascarava-o.
    return hoje == 0
        ? 'Nada concluído ontem nem hoje'
        : 'Igual a ontem ($ontem)';
  }
  final sinal = diferenca > 0 ? '+' : '−';
  return '$sinal${diferenca.abs()} vs ontem ($ontem)';
}

class DashboardPrincipalScreen extends StatefulWidget {
  const DashboardPrincipalScreen({super.key, this.aoAbrirOrdens});

  /// Pedido para mostrar as ordens por trás de um KPI, já filtradas.
  ///
  /// O dashboard não navega sozinho: os ecrãs vivem num `IndexedStack` e é o
  /// shell que decide qual está à frente. Nulo deixa os cartões só de leitura,
  /// que é o que interessa se este ecrã for reutilizado fora do shell.
  final void Function(FiltroEstadoOrdem filtro)? aoAbrirOrdens;

  @override
  State<DashboardPrincipalScreen> createState() =>
      _DashboardPrincipalScreenState();
}

class _DashboardPrincipalScreenState extends State<DashboardPrincipalScreen> {
  final _encomendasRepo = EncomendasRepository();
  final _fluxosRepo = FluxosRepository();
  final _postosRepo = PostosRepository();

  RealtimeChannel? _factorySubscription;
  RealtimeChannel? _postosSubscription;
  Timer? _everySecondTimer;

  bool _isLoading = true;

  /// Motivo da última falha de carregamento, ou `null` se a última leitura
  /// correu bem. Enquanto não for `null`, o ecrã diz-lo — antes, a falha
  /// passava por um `debugPrint` e o utilizador via zeros que pareciam reais.
  String? _erroCarregamento;

  /// Distingue "ainda não conseguimos carregar nada" de "falhou a atualização
  /// do que já está no ecrã": o primeiro caso substitui o ecrã pelo estado de
  /// erro, o segundo mostra só uma barra por cima dos dados antigos.
  bool _carregouUmaVez = false;

  // KPIs de Produção
  int _encomendasAtivas = 0;
  int _encomendasAtrasadas = 0;
  int _concluidasHoje = 0;

  /// Ordens que fecharam ontem, para dar escala ao número de hoje.
  ///
  /// É o único KPI deste ecrã com comparação: os outros quatro são fotografias
  /// do estado atual (`fase_atual_id`, `em_suspenso`, `postos_trabalho.estado`)
  /// e a base de dados não guarda o estado de ontem em lado nenhum. Inventar
  /// uma variação a partir do que existe hoje seria uma comparação falsa.
  int _concluidasOntem = 0;

  /// Ordens suspensas (WIP Hold). Estavam só visíveis dentro dos alertas.
  int _encomendasEmHold = 0;

  /// Ordens já concluídas e, dessas, quantas o cliente confirmou ter recebido.
  ///
  /// Mede o fecho da rastreabilidade fora da fábrica: uma ordem concluída sem
  /// receção confirmada percorreu o roteiro todo mas não tem prova de ter
  /// chegado ao destinatário.
  int _totalConcluidas = 0;
  int _rececoesConfirmadas = 0;

  /// Percentagem de postos que não estão em estado 'Parado'.
  double _disponibilidadePostos = 100.0;

  /// Quantos postos estão 'Parado' agora — dá contexto à percentagem.
  int _postosParados = 0;
  int _totalPostos = 0;

  /// Critério de ordenação do Pareto das paragens, escolhido pelo utilizador.
  ///
  /// Trocar de critério não volta à rede: `ParagemAgregada` já traz as
  /// ocorrências e os minutos totais de cada motivo.
  CriterioPareto _criterioPareto = CriterioPareto.ocorrencias;

  /// Ordens ativas em cada posto físico da fábrica.
  List<OcupacaoPosto> _ocupacaoPostos = [];

  // Alertas de Incidência Ativos
  List<Map<String, dynamic>> _alertasIncidencias = [];

  /// Motivos de paragem mais frequentes do último mês (análise de Pareto).
  List<ParagemAgregada> _paretoParagens = [];

  /// Janela do Pareto, em dias. Fixa por agora, mas nomeada porque aparece
  /// tanto na query como no subtítulo do cartão.
  static const int _diasPareto = 30;

  @override
  void initState() {
    super.initState();
    _carregarDadosDashboard();
    _inicializarSubscricaoTempoReal();

    // Serve apenas para refrescar os contadores "há X min" dos alertas.
    // Estava a 1 segundo, o que reconstruía o dashboard inteiro 60x por minuto.
    _everySecondTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _alertasIncidencias.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _everySecondTimer?.cancel();
    _recarregador.descartar();
    if (_factorySubscription != null) {
      _encomendasRepo.client.removeChannel(_factorySubscription!);
    }
    if (_postosSubscription != null) {
      _postosRepo.client.removeChannel(_postosSubscription!);
    }
    super.dispose();
  }

  /// Junta os eventos de uma rajada num só recarregamento.
  ///
  /// Todos os números deste ecrã são agregados sobre o conjunto inteiro
  /// (ocupação por fase, disponibilidade, atrasadas, concluídas hoje): não há
  /// como os incrementar a partir de um evento isolado sem arriscar deriva
  /// acumulada, e cada recarregamento custa cinco queries. Aqui a resposta é só o debounce —
  /// mas com janela larga, porque estes indicadores são de leitura e não de
  /// reação. A primeira alteração continua a aparecer de imediato.
  late final RecarregadorDebounced _recarregador = RecarregadorDebounced(
    aoRecarregar: _carregarDadosDashboard,
    janela: janelaRealtimeAgregado,
    tetoEspera: tetoRealtimeAgregado,
  );

  /// ⚡ Liga o canal de escuta em tempo real às tabelas de encomendas e incidências
  void _inicializarSubscricaoTempoReal() {
    _factorySubscription = _encomendasRepo.escutarProducao(
      'db-factory-changes',
      (_) => _recarregador.pedir(),
    );
    // A disponibilidade passou a vir de `postos_trabalho.estado`, que muda sem
    // tocar em encomendas nem incidências. Canal separado (é outra tabela), mas
    // alimenta o mesmo recarregador — não há um segundo mecanismo de atualização.
    _postosSubscription = _postosRepo.escutar(
      'db-postos-changes',
      _recarregador.pedir,
    );
  }

  /// Carrega e calcula todas as métricas com base no teu esquema relacional real
  Future<void> _carregarDadosDashboard() async {
    try {
      if (!mounted) return;

      // 1. Traduz cada fase do roteiro no posto físico que a executa. O gráfico
      // deixou de ser por `nome_fase_padrao`: esse nome repete-se entre
      // roteiros de produtos diferentes e a barra não correspondia a nenhum
      // recurso real da fábrica.
      final Map<int, int> postoPorFase = await _fluxosRepo.obterPostoPorFase();

      // 2. Carrega as encomendas trazendo o nome da fase onde se encontram atualmente
      // Ordens canceladas não contam para nenhum indicador operacional.
      final List<EncomendaModel> encomendas = await _encomendasRepo
          .obterParaDashboard();

      // 3. Carrega as incidências ativas (as resolvidas não são paragens)
      final List<Map<String, dynamic>> incidenciasRaw = await _encomendasRepo
          .obterIncidenciasAbertas();

      // 3b. Motivos de paragem mais frequentes do último mês. Inclui as já
      // resolvidas de propósito: o Pareto serve para decidir onde atacar a
      // causa raiz, e uma avaria que se repete e se resolve depressa é
      // exatamente o que se quer ver.
      final List<ParagemAgregada> pareto = await _encomendasRepo
          .obterParetoParagens(dias: _diasPareto);

      if (!mounted) return;

      int ativas = 0;
      int atrasadas = 0;
      int emHold = 0;
      int rececoesConfirmadas = 0;

      // Ordens já concluídas, para depois as datar pelo dia em que fecharam.
      final Set<int> idsConcluidas = {};

      // Fase onde está cada ordem na linha — uma entrada por ordem, com
      // repetições, porque duas ordens no mesmo posto contam duas vezes.
      final List<int> fasesAtuais = [];

      final DateTime hoje = DateTime.now();

      final DateTime ontem = hoje.subtract(const Duration(days: 1));

      // 4. Última fase concluída de cada ordem nos dois dias. Uma janela só,
      // em vez de uma leitura por dia: são poucas linhas e evita que os dois
      // lados da comparação venham de instantes diferentes.
      final Map<int, DateTime> ultimasConclusoes = await _encomendasRepo
          .obterUltimasConclusoes(desde: ontem, ate: hoje);

      // 5. Processamento posicional das encomendas
      //
      // A classificação passa por [EstadoOrdem.derivar] em vez de reler
      // `fase_atual_id` à mão: é a mesma regra que o painel de controlo e os
      // relatórios usam, e é o que permite separar as ordens em hold das que
      // estão mesmo a produzir — antes ambas caíam em "ativas" sem distinção.
      for (final enc in encomendas) {
        final estado = enc.estado;

        if (estado == EstadoOrdem.concluida) {
          // Concluída: não ocupa posto nenhum. Em que dia fechou decide-se
          // mais abaixo, pela data da última fase.
          idsConcluidas.add(enc.id);

          // Fecho do ciclo do lado do destinatário. Conta-se sobre as
          // concluídas, e não sobre todas as ordens, porque só essas podem
          // ter sido recebidas.
          if (enc.dataConfirmacaoRececao != null) rececoesConfirmadas++;
        } else {
          // Em produção ou suspensa: continua a ocupar um posto na linha.
          ativas++;
          if (estado == EstadoOrdem.emHold) emHold++;

          // Posição estrita: a ordem conta só no posto onde está agora, e as
          // suspensas contam na mesma — continuam a ocupar o posto.
          final int? faseAtual = enc.faseAtualId;
          if (faseAtual != null) fasesAtuais.add(faseAtual);

          // Verifica se a encomenda ativa está atrasada
          final DateTime? prazo = enc.dataEntrega;
          if (prazo != null) {
            final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
            if (hojeSemHoras.isAfter(prazo)) {
              atrasadas++;
            }
          }
        }
      }

      // 5b. Ritmo de saída: quantas ordens fecharam hoje e quantas fecharam
      // ontem, pela mesma regra.
      final int concluidasHoje = EncomendasRepository.contarConcluidasEm(
        hoje,
        idsConcluidas: idsConcluidas,
        ultimasConclusoes: ultimasConclusoes,
      );
      final int concluidasOntem = EncomendasRepository.contarConcluidasEm(
        ontem,
        idsConcluidas: idsConcluidas,
        ultimasConclusoes: ultimasConclusoes,
      );

      // 6. Disponibilidade dos postos de trabalho.
      //
      // Lê-se a coluna `postos_trabalho.estado` em vez de a inferir a partir das
      // incidências abertas: um posto pode estar 'Parado' por setup, falta de
      // material ou operador sem que exista incidência, e o denominador antigo
      // eram nomes de fase (que se repetem entre produtos), não postos físicos.
      // Isto é só a Disponibilidade — não é OEE, que exigiria também
      // Performance (tempo_estimado vs real) e Qualidade.
      final List<PostoResumo> postos = await _postosRepo.obterResumo();

      if (!mounted) return;

      final Map<String, int> postosPorEstado = PostosRepository.contarPorEstado(
        postos,
      );
      final List<OcupacaoPosto> ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: postoPorFase,
        fasesAtuais: fasesAtuais,
      );

      final int totalPostos = postosPorEstado.values.fold(
        0,
        (soma, n) => soma + n,
      );
      final int postosParados = postosPorEstado[EstadoPosto.parado] ?? 0;
      final double disponibilidade = totalPostos > 0
          ? (((totalPostos - postosParados) / totalPostos) * 100).clamp(
              0.0,
              100.0,
            )
          : 100.0;

      setState(() {
        _encomendasAtivas = ativas;
        _encomendasAtrasadas = atrasadas;
        _concluidasHoje = concluidasHoje;
        _concluidasOntem = concluidasOntem;
        _encomendasEmHold = emHold;
        _totalConcluidas = idsConcluidas.length;
        _rececoesConfirmadas = rececoesConfirmadas;
        _disponibilidadePostos = disponibilidade;
        _postosParados = postosParados;
        _totalPostos = totalPostos;
        _ocupacaoPostos = ocupacao;
        _alertasIncidencias = List<Map<String, dynamic>>.from(incidenciasRaw);
        _paretoParagens = pareto;
        _isLoading = false;
        _erroCarregamento = null;
        _carregouUmaVez = true;
      });
    } catch (e) {
      debugPrint('❌ Erro ao processar dados do dashboard: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _erroCarregamento = descreverErro(e);
        });
      }
    }
  }

  String _calcularTempoDowntime(String dataCriacaoStr) {
    try {
      final DateTime dataCriacao = DateTime.parse(dataCriacaoStr);
      final Duration diferenca = DateTime.now().difference(dataCriacao);

      if (diferenca.inMinutes < 60) {
        return '${diferenca.inMinutes}m atrás';
      } else if (diferenca.inHours < 24) {
        return '${diferenca.inHours}h ${diferenca.inMinutes % 60}m atrás';
      } else {
        return '${diferenca.inDays} dias atrás';
      }
    } catch (_) {
      return 'Agora mesmo';
    }
  }

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    // Sem nada carregado, os KPIs a zero seriam indistinguíveis de uma fábrica
    // parada: o ecrã inteiro passa a ser o estado de erro.
    if (!_isLoading && _erroCarregamento != null && !_carregouUmaVez) {
      return Scaffold(
        backgroundColor: TemasCores.fundoEcraFrio,
        body: EstadoErro(
          titulo: 'Não foi possível carregar os indicadores de produção',
          detalhe: _erroCarregamento,
          aoRepetir: () {
            setState(() => _isLoading = true);
            _carregarDadosDashboard();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: paddingEcra(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  // Os números continuam visíveis, mas ficam marcados como
                  // possivelmente desatualizados em vez de mentirem em silêncio.
                  if (_erroCarregamento != null)
                    EstadoErro.compacto(
                      titulo:
                          'Os indicadores podem estar desatualizados — falhou a última atualização.',
                      detalhe: _erroCarregamento,
                      aoRepetir: _carregarDadosDashboard,
                    ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // `constraints.maxWidth` e não a largura do ecrã: a
                      // sidebar do painel ocupa 260 px, e a documentação de
                      // [_colunasKpi] fala de largura *disponível* — era essa
                      // a intenção, mas o valor que chegava era o do ecrã
                      // inteiro, o que dava cinco cartões de ~200 px num
                      // espaço onde só cabiam três legíveis.
                      final int colunas = _colunasKpi(constraints.maxWidth);
                      return GridView(
                        // Altura fixa, não proporção: o conteúdo (título +
                        // valor + até 2 linhas de subtítulo) tem sempre a
                        // mesma altura, seja qual for a largura do cartão —
                        // com `childAspectRatio` (GridView.count), a 1 coluna
                        // o cartão ficava demasiado baixo e o texto estourava
                        // por baixo.
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: colunas,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 132,
                        ),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildKpiCard(
                            titulo: 'Encomendas Ativas',
                            valor: '$_encomendasAtivas',
                            subtitulo: 'Na linha (inclui as em hold)',
                            corIcone: TemasCores.infoForte,
                            fundoIcone: TemasCores.infoFundo,
                            icone: Icons.precision_manufacturing_outlined,
                          ),
                          _buildKpiCard(
                            titulo: 'Encomendas Atrasadas',
                            valor: '$_encomendasAtrasadas',
                            subtitulo: 'Prazo de entrega expirado',
                            corIcone: TemasCores.erroForte,
                            fundoIcone: TemasCores.erroFundo,
                            icone: Icons.warning_amber_rounded,
                            alerta: _encomendasAtrasadas > 0,
                            filtro: FiltroEstadoOrdem.atrasada,
                          ),
                          _buildKpiCard(
                            titulo: 'Encomendas em Hold',
                            valor: '$_encomendasEmHold',
                            subtitulo: 'Suspensas por WIP Hold',
                            corIcone: TemasCores.avisoTextoForte,
                            fundoIcone: TemasCores.avisoFundo,
                            icone: Icons.pause_circle_outline,
                            alerta: _encomendasEmHold > 0,
                            filtro: FiltroEstadoOrdem.emHold,
                          ),
                          _buildKpiCard(
                            titulo: 'Concluídas Hoje',
                            valor: '$_concluidasHoje',
                            subtitulo: descreverVariacaoDiaria(
                              _concluidasHoje,
                              _concluidasOntem,
                            ),
                            corIcone: TemasCores.sucessoForte,
                            fundoIcone: TemasCores.sucessoFundo,
                            icone: Icons.check_circle_outline,
                          ),
                          _buildKpiCard(
                            titulo: 'Disponibilidade de Postos',
                            valor:
                                '${_disponibilidadePostos.toStringAsFixed(0)}%',
                            subtitulo: _totalPostos == 0
                                ? 'Sem postos registados'
                                : '% de postos operacionais · $_postosParados de $_totalPostos parados',
                            corIcone: TemasCores.adminAcentoForte,
                            fundoIcone: TemasCores.adminAcentoFundo,
                            icone: Icons.bolt_outlined,
                            alerta: _disponibilidadePostos < 90,
                          ),
                          _buildKpiCard(
                            titulo: 'Entregas Confirmadas',
                            valor: _totalConcluidas == 0
                                ? '—'
                                : '${((_rececoesConfirmadas / _totalConcluidas) * 100).toStringAsFixed(0)}%',
                            subtitulo: _totalConcluidas == 0
                                ? 'Ainda sem ordens concluídas'
                                : '$_rececoesConfirmadas de $_totalConcluidas concluídas recebidas',
                            corIcone: TemasCores.sucessoForte,
                            fundoIcone: TemasCores.sucessoFundo,
                            icone: Icons.inventory_2_outlined,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  eDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: _buildChartCard()),
                            const SizedBox(width: 24),
                            Expanded(flex: 2, child: _buildIncidentsCard()),
                          ],
                        )
                      : Column(
                          children: [
                            _buildChartCard(),
                            const SizedBox(height: 24),
                            _buildIncidentsCard(),
                          ],
                        ),
                  const SizedBox(height: 24),
                  _buildParetoCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Painel de Controlo Operacional',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.textoPrimario,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: TemasCores.sucesso,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: Text(
                      'Ligação ao Chão de Fábrica Ativa',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: TemasCores.textoApoio,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _carregarDadosDashboard,
          icon: const Icon(
            Icons.refresh_rounded,
            color: TemasCores.adminAcento,
          ),
          tooltip: 'Forçar Sincronização',
        ),
      ],
    );
  }

  /// Número de colunas da grelha de KPIs para a largura disponível.
  ///
  /// Com o quinto cartão (em hold), pôr cinco colunas logo aos 1100 px deixava
  /// cada cartão com ~200 px — estreito de mais para o valor e o subtítulo. Só
  /// acima dos 1500 px é que os cinco cabem lado a lado; entre os dois, três
  /// colunas mantêm-nos legíveis mesmo que a segunda linha fique incompleta.
  static int _colunasKpi(double largura) {
    if (largura < 600) return 1;
    if (largura < 1100) return 2;
    if (largura < 1500) return 3;
    return 5;
  }

  /// Um cartão de KPI, navegável quando [filtro] identifica as ordens que estão
  /// por trás do número.
  ///
  /// Só "Atrasadas" e "Em Hold" o são: são os dois KPIs que exigem uma decisão
  /// e cujas ordens o painel de controlo sabe listar. "Ativas" corresponderia a
  /// quase toda a lista, e a disponibilidade é sobre postos, não sobre ordens.
  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required Color corIcone,
    required Color fundoIcone,
    required IconData icone,
    bool alerta = false,
    FiltroEstadoOrdem? filtro,
  }) {
    final aoAbrir = widget.aoAbrirOrdens;
    final navegavel = filtro != null && aoAbrir != null;

    return CartaoKpi(
      estilo: EstiloKpi.principal,
      titulo: titulo,
      valor: valor,
      subtitulo: subtitulo,
      icone: icone,
      corIcone: corIcone,
      fundoIcone: fundoIcone,
      alerta: alerta,
      aoTocar: navegavel ? () => aoAbrir(filtro) : null,
      dicaToque: navegavel ? 'Ver as ordens em "${filtro.etiqueta}"' : null,
    );
  }

  Widget _buildChartCard() {
    final int valorMaximo = _ocupacaoPostos.fold(
      0,
      (max, o) => o.ordens > max ? o.ordens : max,
    );
    const double alturaGrafico = 250.0;

    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ocupação dos Postos de Trabalho',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Encomendas ativas em cada posto físico · a vermelho, postos parados',
              style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
            ),
            const SizedBox(height: 32),
            if (_ocupacaoPostos.isEmpty)
              const SizedBox(
                height: alturaGrafico,
                child: Center(
                  child: Text(
                    'Sem postos de trabalho registados.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TemasCores.textoTerciario,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: alturaGrafico,
                // Cada barra era um `Expanded`: com vários postos num ecrã
                // estreito, cada coluna ficava tão fina que o nome do posto
                // não cabia nem como uma palavra só e quebrava a meio
                // ("Lixage" / "m") — o gráfico parecia torto. Com largura
                // mínima por coluna, ganha scroll horizontal em vez disso.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const larguraColuna = 64.0;
                    final double larguraNecessaria =
                        _ocupacaoPostos.length * larguraColuna;
                    final barras = Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: _construirBarras(valorMaximo, larguraColuna),
                    );
                    if (larguraNecessaria <= constraints.maxWidth) {
                      return barras;
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: larguraNecessaria, child: barras),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _construirBarras(int valorMaximo, double larguraColuna) {
    const double alturaGrafico = 250.0;
    return _ocupacaoPostos.map((ocupacao) {
      final int quantidade = ocupacao.ordens;
      final bool parado = ocupacao.posto.parado;

      final double percentagemAltura = valorMaximo == 0
          ? 0.05
          : (quantidade / valorMaximo);

      return SizedBox(
        width: larguraColuna,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Altura fixa para o número: sem isto, cada valor ficava colado
              // ao topo da sua própria barra — barras mais baixas deixavam o
              // número mais em baixo do que as altas, e a linha de números
              // parecia desalinhada em vez de correr toda à mesma altura.
              SizedBox(
                height: 16,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: quantidade > 0 ? 1.0 : 0.4,
                    child: Text(
                      '$quantidade',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutBack,
                width: 24,
                height: (alturaGrafico - 65) * percentagemAltura,
                decoration: BoxDecoration(
                  // Um posto parado com ordens em cima é o pior
                  // caso do chão de fábrica: a barra diz-se logo,
                  // sem obrigar a cruzar com o cartão de
                  // disponibilidade.
                  gradient: LinearGradient(
                    colors: parado
                        ? const [TemasCores.erroMedio, TemasCores.erroForte]
                        : const [
                            TemasCores.graficoBarraTopo,
                            TemasCores.graficoBarraBase,
                          ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Idem para o rótulo: altura fixa (2 linhas), para um nome de
              // posto com 1 linha só não deixar a barra mais alta que as
              // vizinhas com nomes de 2 linhas.
              SizedBox(
                height: 28,
                child: Text(
                  ocupacao.posto.nome,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: parado ? TemasCores.erroForte : TemasCores.textoApoio,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// Pareto dos motivos de paragem: onde atacar primeiro.
  ///
  /// As barras são relativas ao motivo mais frequente e não ao total, porque o
  /// que interessa é a ordem de grandeza entre eles — com cinco motivos, uma
  /// escala sobre o total deixaria todas as barras curtas e indistinguíveis.
  Widget _buildParetoCard() {
    // Ordena pelo critério escolhido. A lista chega inteira do repositório para
    // a curva acumulada poder ser calculada sobre o total real das paragens, e
    // não sobre o total das cinco que cabem no ecrã.
    final List<ParagemAgregada> ordenadas = EncomendasRepository.ordenarPareto(
      _paretoParagens,
      criterio: _criterioPareto,
    );
    final List<ParagemAgregada> topo = ordenadas.take(5).toList();

    int valorDe(ParagemAgregada p) =>
        _criterioPareto == CriterioPareto.tempoPerdido
        ? p.minutosTotais
        : p.ocorrencias;

    final int valorMaximo = topo.fold(
      0,
      (max, p) => valorDe(p) > max ? valorDe(p) : max,
    );
    final int totalGeral = ordenadas.fold(0, (soma, p) => soma + valorDe(p));

    // MTTR: tempo médio de reparação de todas as paragens do período.
    final int totalOcorrencias = ordenadas.fold(
      0,
      (soma, p) => soma + p.ocorrencias,
    );
    final int totalMinutos = ordenadas.fold(
      0,
      (soma, p) => soma + p.minutosTotais,
    );
    final int mttr = totalOcorrencias == 0
        ? 0
        : (totalMinutos / totalOcorrencias).round();

    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                const Text(
                  'Análise de Paragens (Pareto)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoPrimario,
                  ),
                ),
                SegmentedButton<CriterioPareto>(
                  segments: CriterioPareto.values
                      .map(
                        (c) => ButtonSegment<CriterioPareto>(
                          value: c,
                          label: Text(
                            c.etiqueta,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_criterioPareto},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (selecao) =>
                      setState(() => _criterioPareto = selecao.first),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Top 5 por motivo oficial, nos últimos $_diasPareto dias · '
              'MTTR ${_formatarDuracao(mttr)}',
              style: const TextStyle(
                fontSize: 13,
                color: TemasCores.textoTerciario,
              ),
            ),
            const SizedBox(height: 20),
            if (topo.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Sem paragens com motivo registado no período.',
                    style: TextStyle(
                      fontSize: 12,
                      color: TemasCores.textoTerciario,
                    ),
                  ),
                ),
              )
            else
              // A percentagem acumulada usa o total de todas as paragens do
              // período, não só o das cinco mostradas — é o que permite ler
              // "estes cinco motivos são 80% do problema".
              ...() {
                int acumulado = 0;
                return List.generate(topo.length, (i) {
                  acumulado += valorDe(topo[i]);
                  return _buildLinhaPareto(
                    posicao: i + 1,
                    paragem: topo[i],
                    valor: valorDe(topo[i]),
                    valorMaximo: valorMaximo,
                    percentagemAcumulada: totalGeral == 0
                        ? 0
                        : (acumulado / totalGeral) * 100,
                  );
                });
              }(),
          ],
        ),
      ),
    );
  }

  Widget _buildLinhaPareto({
    required int posicao,
    required ParagemAgregada paragem,
    required int valor,
    required int valorMaximo,
    required double percentagemAcumulada,
  }) {
    final double fracao = valorMaximo == 0 ? 0 : valor / valorMaximo;
    final bool porTempo = _criterioPareto == CriterioPareto.tempoPerdido;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '$posicao.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoTerciario,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  paragem.rotulo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TemasCores.textoPrimario,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                porTempo ? _formatarDuracao(valor) : '$valor×',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.textoSecundario,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fracao,
                    minHeight: 8,
                    backgroundColor: TemasCores.superficieTenue,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      TemasCores.graficoBarraBase,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${paragem.categoria} · ${paragem.ocorrencias}× '
                        '· ${_formatarDuracao(paragem.minutosTotais)} no total '
                        '· ${_formatarDuracao(paragem.minutosMedios)} em média',
                        style: const TextStyle(
                          fontSize: 11,
                          color: TemasCores.textoTerciario,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Curva acumulada: onde este motivo põe o total. A regra
                    // 80/20 lê-se aqui — os motivos até aos 80% são os que
                    // vale a pena atacar primeiro.
                    Text(
                      '${percentagemAcumulada.toStringAsFixed(0)}% acum.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: percentagemAcumulada <= 80
                            ? TemasCores.erroTextoForte
                            : TemasCores.textoTerciario,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Duração em minutos para texto curto: `45 min` ou `2h 05m`.
  static String _formatarDuracao(int minutos) {
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return '${horas}h ${resto.toString().padLeft(2, '0')}m';
  }

  Widget _buildIncidentsCard() {
    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Alertas de Incidência',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: TemasCores.textoPrimario,
                    ),
                  ),
                ),
                if (_alertasIncidencias.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: TemasCores.erroFundo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_alertasIncidencias.length} Paragens',
                      style: const TextStyle(
                        fontSize: 11,
                        color: TemasCores.erroForte,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Paragens registadas no chão de fábrica',
              style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
            ),
            _buildTempoMedioParagem(),
            const SizedBox(height: 20),

            if (_alertasIncidencias.isEmpty)
              _buildSemIncidencias()
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alertasIncidencias.length,
                itemBuilder: (context, index) =>
                    _buildCartaoAlerta(_alertasIncidencias[index]),
              ),
          ],
        ),
      ),
    );
  }

  /// Há quanto tempo, em média, as paragens abertas estão a bloquear a linha.
  ///
  /// É calculado no `build` e não guardado no estado de propósito: o contador
  /// "há X min" de cada cartão avança de 30 em 30 segundos com o timer, e uma
  /// média congelada até ao próximo recarregamento passaria a contradizer os
  /// cartões que tem por baixo.
  Widget _buildTempoMedioParagem() {
    if (_alertasIncidencias.isEmpty) return const SizedBox.shrink();

    final media = EncomendasRepository.tempoMedioParagemAberta(
      _alertasIncidencias.map(IncidenciaModel.fromJson).toList(),
    );
    if (media == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: TemasCores.erroFundo,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.timer_outlined,
              size: 16,
              color: TemasCores.erroForte,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tempo médio de paragem ativa: ${_formatarDuracao(media.inMinutes)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: TemasCores.erroForte,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Estado vazio: nenhuma paragem em aberto.
  Widget _buildSemIncidencias() {
    return const SizedBox(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gpp_good_outlined, size: 48, color: TemasCores.sucesso),
            SizedBox(height: 12),
            Text(
              'Chão de Fábrica a 100%!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: TemasCores.sucesso,
              ),
            ),
            Text(
              'Sem paragens ou bloqueios reportados.',
              style: TextStyle(color: TemasCores.textoTerciario, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Extrai a referência da encomenda, o posto e o operador de uma incidência.
  ///
  /// A incidência liga-se a estes dados através de `historico_producao`, pelo que
  /// as junções vêm encadeadas e podem faltar em qualquer nível.
  ({String encRef, String posto, String operador}) _dadosAlerta(
    Map<String, dynamic> inc,
  ) {
    final hist = inc['historico_producao'];
    if (hist == null) {
      return (
        encRef: 'N/A',
        posto: 'Não especificado',
        operador: 'Desconhecido',
      );
    }

    final encData = hist['encomendas'];
    final encId = hist['encomenda_id'];
    final faseData = hist['fases_padrao'];
    final userData = hist['utilizadores'];

    return (
      encRef: encData != null
          ? (encData['codigo_rastreio'] ?? 'N/A')
          : (encId != null ? '#$encId' : 'N/A'),
      posto: faseData != null
          ? (faseData['posto_trabalho'] ?? 'Não especificado')
          : 'Não especificado',
      operador: userData != null
          ? (userData['nome_utilizador'] ?? 'Desconhecido')
          : 'Desconhecido',
    );
  }

  /// Cartão de uma paragem ativa no chão de fábrica.
  Widget _buildCartaoAlerta(Map<String, dynamic> inc) {
    final dados = _dadosAlerta(inc);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: TemasCores.erroForte,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Enc. ${dados.encRef}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: TemasCores.erroFundoForte,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ATENÇÃO',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.erro,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Posto: ${dados.posto}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: TemasCores.textoSecundario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  inc['motivo'] ?? 'Sem motivo indicado.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: TemasCores.textoApoio,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '⏱️ Ativo: ${_calcularTempoDowntime(inc['created_at'] ?? DateTime.now().toIso8601String())}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: TemasCores.erroMedio,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Op: ${dados.operador}',
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 11,
                          color: TemasCores.textoDesativado,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
