import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/postos_repository.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/cartao_kpi.dart';

class DashboardPrincipalScreen extends StatefulWidget {
  const DashboardPrincipalScreen({super.key});

  @override
  State<DashboardPrincipalScreen> createState() => _DashboardPrincipalScreenState();
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

  /// Ordens suspensas (WIP Hold). Estavam só visíveis dentro dos alertas.
  int _encomendasEmHold = 0;

  /// Percentagem de postos que não estão em estado 'Parado'.
  double _disponibilidadePostos = 100.0;

  /// Quantos postos estão 'Parado' agora — dá contexto à percentagem.
  int _postosParados = 0;
  int _totalPostos = 0;

  // Distribuição de Encomendas por Fase (Ocupação Estrita por Posto)
  Map<String, int> _fasesDistribuicao = {};

  // Alertas de Incidência Ativos
  List<Map<String, dynamic>> _alertasIncidencias = [];

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

      // 1. Carrega todas as fases padrão definidas no sistema (para estruturar o gráfico)
      final List<Map<String, dynamic>> fasesPadrao = await _fluxosRepo.obterNomesDasFases();

      Map<String, int> tempFases = {};
      for (var f in fasesPadrao) {
        final String nome = f['nome_fase_padrao'] ?? '';
        if (nome.isNotEmpty) {
          tempFases[nome] = 0; // Inicializa todos os postos de trabalho a zeros
        }
      }

      if (tempFases.isEmpty) {
        tempFases = {
          'Corte': 0,
          'Montagem': 0,
          'Acabamento': 0,
          'Controlo': 0,
          'Embalagem': 0,
        };
      }

      // 2. Carrega as encomendas trazendo o nome da fase onde se encontram atualmente
      // Ordens canceladas não contam para nenhum indicador operacional.
      final List<EncomendaModel> encomendas = await _encomendasRepo.obterParaDashboard();

      // 3. Carrega as incidências ativas (as resolvidas não são paragens)
      final List<Map<String, dynamic>> incidenciasRaw = await _encomendasRepo.obterIncidenciasAbertas();

      if (!mounted) return;

      int ativas = 0;
      int atrasadas = 0;
      int concluidasHoje = 0;
      int emHold = 0;

      final DateTime hoje = DateTime.now();

      // 4. Carrega o histórico de produção do dia para validar encomendas finalizadas hoje
      final List<Map<String, dynamic>> historicoHoje = await _encomendasRepo.obterHistoricoDoDia(hoje);

      final Set<int> encomendasAtivasHojeIds = historicoHoje
          .map((h) => h['encomenda_id'] is int ? h['encomenda_id'] as int : int.tryParse(h['encomenda_id'].toString()) ?? 0)
          .toSet();

      // 5. Processamento posicional das encomendas
      //
      // A classificação passa por [EstadoOrdem.derivar] em vez de reler
      // `fase_atual_id` à mão: é a mesma regra que o painel de controlo e os
      // relatórios usam, e é o que permite separar as ordens em hold das que
      // estão mesmo a produzir — antes ambas caíam em "ativas" sem distinção.
      for (final enc in encomendas) {
        final estado = enc.estado;

        if (estado == EstadoOrdem.concluida) {
          // Encomenda Concluída (Não aparece em nenhuma barra ativa)
          if (encomendasAtivasHojeIds.contains(enc.id)) {
            concluidasHoje++;
          }
        } else {
          // Em produção ou suspensa: continua a ocupar um posto na linha.
          ativas++;
          if (estado == EstadoOrdem.emHold) emHold++;

          // 📊 LÓGICA DE POSIÇÃO ESTRITA: Soma +1 APENAS na barra da fase atual onde o produto está parado
          final String nomeFase = enc.nomeFaseAtual ?? '';
          if (nomeFase.isNotEmpty && tempFases.containsKey(nomeFase)) {
            tempFases[nomeFase] = (tempFases[nomeFase] ?? 0) + 1;
          }

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

      // 6. Disponibilidade dos postos de trabalho.
      //
      // Lê-se a coluna `postos_trabalho.estado` em vez de a inferir a partir das
      // incidências abertas: um posto pode estar 'Parado' por setup, falta de
      // material ou operador sem que exista incidência, e o denominador antigo
      // eram nomes de fase (que se repetem entre produtos), não postos físicos.
      // Isto é só a Disponibilidade — não é OEE, que exigiria também
      // Performance (tempo_estimado vs real) e Qualidade.
      final Map<String, int> postosPorEstado = await _postosRepo.contarPorEstado();

      if (!mounted) return;

      final int totalPostos =
          postosPorEstado.values.fold(0, (soma, n) => soma + n);
      final int postosParados = postosPorEstado[EstadoPosto.parado] ?? 0;
      final double disponibilidade = totalPostos > 0
          ? (((totalPostos - postosParados) / totalPostos) * 100).clamp(0.0, 100.0)
          : 100.0;

      setState(() {
        _encomendasAtivas = ativas;
        _encomendasAtrasadas = atrasadas;
        _concluidasHoje = concluidasHoje;
        _encomendasEmHold = emHold;
        _disponibilidadePostos = disponibilidade;
        _postosParados = postosParados;
        _totalPostos = totalPostos;
        _fasesDistribuicao = tempFases;
        _alertasIncidencias = List<Map<String, dynamic>>.from(incidenciasRaw);
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
        backgroundColor: TemasCores.fundoEcra,
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
      backgroundColor: TemasCores.fundoEcra,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  // Os números continuam visíveis, mas ficam marcados como
                  // possivelmente desatualizados em vez de mentirem em silêncio.
                  if (_erroCarregamento != null)
                    EstadoErro.compacto(
                      titulo: 'Os indicadores podem estar desatualizados — falhou a última atualização.',
                      detalhe: _erroCarregamento,
                      aoRepetir: _carregarDadosDashboard,
                    ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final int colunas = _colunasKpi(larguraEcra);
                      return GridView.count(
                        crossAxisCount: colunas,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: _proporcaoKpi(colunas),
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
                          ),
                          _buildKpiCard(
                            titulo: 'Encomendas em Hold',
                            valor: '$_encomendasEmHold',
                            subtitulo: 'Suspensas por WIP Hold',
                            corIcone: TemasCores.avisoTextoForte,
                            fundoIcone: TemasCores.avisoFundo,
                            icone: Icons.pause_circle_outline,
                            alerta: _encomendasEmHold > 0,
                          ),
                          _buildKpiCard(
                            titulo: 'Concluídas Hoje',
                            valor: '$_concluidasHoje',
                            subtitulo: 'Finalizadas nas últimas 24h',
                            corIcone: TemasCores.sucessoForte,
                            fundoIcone: TemasCores.sucessoFundo,
                            icone: Icons.check_circle_outline,
                          ),
                          _buildKpiCard(
                            titulo: 'Disponibilidade de Postos',
                            valor: '${_disponibilidadePostos.toStringAsFixed(0)}%',
                            subtitulo: _totalPostos == 0
                                ? 'Sem postos registados'
                                : '% de postos operacionais · $_postosParados de $_totalPostos parados',
                            corIcone: TemasCores.acentoRoxoForte,
                            fundoIcone: TemasCores.acentoRoxoFundo,
                            icone: Icons.bolt_outlined,
                            alerta: _disponibilidadePostos < 90,
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
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Painel de Controlo Operacional',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
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
                const Text(
                  'Ligação ao Chão de Fábrica Ativa',
                  style: TextStyle(fontSize: 13, color: TemasCores.textoApoio, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        IconButton(
          onPressed: _carregarDadosDashboard,
          icon: const Icon(Icons.refresh_rounded),
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

  /// Proporção de cada cartão de KPI: quanto menos colunas, mais largo fica o
  /// cartão, pelo que a proporção tem de acompanhar para a altura não disparar.
  static double _proporcaoKpi(int colunas) => switch (colunas) {
        1 => 4.0,
        2 => 2.6,
        3 => 2.4,
        _ => 1.9,
      };

  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required Color corIcone,
    required Color fundoIcone,
    required IconData icone,
    bool alerta = false,
  }) {
    return CartaoKpi(
      estilo: EstiloKpi.principal,
      titulo: titulo,
      valor: valor,
      subtitulo: subtitulo,
      icone: icone,
      corIcone: corIcone,
      fundoIcone: fundoIcone,
      alerta: alerta,
    );
  }

  Widget _buildChartCard() {
    final int valorMaximo = _fasesDistribuicao.values.fold(0, (max, e) => e > max ? e : max);
    const double alturaGrafico = 250.0;

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
              'Distribuição por Fase de Produção',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quantidade de encomendas atualmente ativas em cada etapa',
              style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: alturaGrafico,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _fasesDistribuicao.entries.map((entry) {
                  final String fase = entry.key;
                  final int quantidade = entry.value;

                  final double percentagemAltura = valorMaximo == 0 ? 0.05 : (quantidade / valorMaximo);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            opacity: quantidade > 0 ? 1.0 : 0.4,
                            child: Text(
                              '$quantidade',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutBack,
                            width: 24,
                            height: (alturaGrafico - 65) * percentagemAltura,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  TemasCores.graficoBarraTopo,
                                  TemasCores.graficoBarraBase,
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(4),
                                topRight: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            fase,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: TemasCores.textoApoio),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentsCard() {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Alertas de Incidência',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                ),
                if (_alertasIncidencias.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: TemasCores.erroFundo,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_alertasIncidencias.length} Paragens',
                      style: const TextStyle(fontSize: 11, color: TemasCores.erroForte, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Paragens registadas no chão de fábrica',
              style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
            ),
            const SizedBox(height: 20),

            if (_alertasIncidencias.isEmpty)
              _buildSemIncidencias()
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _alertasIncidencias.length,
                itemBuilder: (context, index) => _buildCartaoAlerta(_alertasIncidencias[index]),
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
              style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.sucesso),
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
  ({String encRef, String posto, String operador}) _dadosAlerta(Map<String, dynamic> inc) {
    final hist = inc['historico_producao'];
    if (hist == null) {
      return (encRef: 'N/A', posto: 'Não especificado', operador: 'Desconhecido');
    }

    final encData = hist['encomendas'];
    final encId = hist['encomenda_id'];
    final faseData = hist['fases_padrao'];
    final userData = hist['utilizadores'];

    return (
      encRef: encData != null
          ? (encData['codigo_rastreio'] ?? 'N/A')
          : (encId != null ? '#$encId' : 'N/A'),
      posto: faseData != null ? (faseData['posto_trabalho'] ?? 'Não especificado') : 'Não especificado',
      operador: userData != null ? (userData['nome_utilizador'] ?? 'Desconhecido') : 'Desconhecido',
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
          const Icon(Icons.error_outline_rounded, color: TemasCores.erroForte, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Enc. ${dados.encRef}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: TemasCores.erroFundoForte,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ATENÇÃO',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: TemasCores.erro),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Posto: ${dados.posto}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: TemasCores.textoSecundario),
                ),
                const SizedBox(height: 2),
                Text(
                  inc['motivo'] ?? 'Sem motivo indicado.',
                  style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '⏱️ Ativo: ${_calcularTempoDowntime(inc['created_at'] ?? DateTime.now().toIso8601String())}',
                      style: const TextStyle(
                          fontSize: 11, color: TemasCores.erroMedio, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Op: ${dados.operador}',
                      style: const TextStyle(fontSize: 11, color: TemasCores.textoDesativado),
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