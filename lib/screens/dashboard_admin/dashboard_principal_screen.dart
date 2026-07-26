import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../models/encomenda_model.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';

class DashboardPrincipalScreen extends StatefulWidget {
  const DashboardPrincipalScreen({super.key});

  @override
  State<DashboardPrincipalScreen> createState() => _DashboardPrincipalScreenState();
}

class _DashboardPrincipalScreenState extends State<DashboardPrincipalScreen> {
  final _encomendasRepo = EncomendasRepository();
  final _fluxosRepo = FluxosRepository();

  RealtimeChannel? _factorySubscription;
  Timer? _everySecondTimer;

  bool _isLoading = true;

  // KPIs de Produção & OEE
  int _encomendasAtivas = 0;
  int _encomendasAtrasadas = 0;
  int _concluidasHoje = 0;
  double _disponibilidadeOEE = 100.0;

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
    if (_factorySubscription != null) {
      _encomendasRepo.client.removeChannel(_factorySubscription!);
    }
    super.dispose();
  }

  /// ⚡ Liga o canal de escuta em tempo real às tabelas de encomendas e incidências
  void _inicializarSubscricaoTempoReal() {
    _factorySubscription = _encomendasRepo.escutarProducao('db-factory-changes', () {
      debugPrint('⚡ [Realtime] Alteração na produção! Recarregando...');
      _carregarDadosDashboard();
    });
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
      
      final DateTime hoje = DateTime.now();

      // 4. Carrega o histórico de produção do dia para validar encomendas finalizadas hoje
      final List<Map<String, dynamic>> historicoHoje = await _encomendasRepo.obterHistoricoDoDia(hoje);

      final Set<int> encomendasAtivasHojeIds = historicoHoje
          .map((h) => h['encomenda_id'] is int ? h['encomenda_id'] as int : int.tryParse(h['encomenda_id'].toString()) ?? 0)
          .toSet();

      // 5. Processamento posicional das encomendas
      for (final enc in encomendas) {
        if (enc.faseAtualId == null) {
          // Encomenda Concluída (Não aparece em nenhuma barra ativa)
          if (encomendasAtivasHojeIds.contains(enc.id)) {
            concluidasHoje++;
          }
        } else {
          // Encomenda ATIVA!
          ativas++;

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

      // 6. Cálculo da Disponibilidade de Postos de Trabalho (OEE)
      final Set<String> postosBloqueados = {};
      for (var inc in incidenciasRaw) {
        final hist = inc['historico_producao'];
        if (hist != null && hist['fases_padrao'] != null) {
          final String? posto = hist['fases_padrao']['posto_trabalho'] as String?;
          if (posto != null && posto.isNotEmpty) {
            postosBloqueados.add(posto);
          }
        }
      }

      final int totalPostos = tempFases.length;
      final double disponibilidade = totalPostos > 0
          ? (((totalPostos - postosBloqueados.length) / totalPostos) * 100).clamp(0.0, 100.0)
          : 100.0;

      setState(() {
        _encomendasAtivas = ativas;
        _encomendasAtrasadas = atrasadas;
        _concluidasHoje = concluidasHoje;
        _disponibilidadeOEE = disponibilidade;
        _fasesDistribuicao = tempFases;
        _alertasIncidencias = List<Map<String, dynamic>>.from(incidenciasRaw);
        _isLoading = false;
      });

    } catch (e) {
      debugPrint('❌ Erro ao processar dados do dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GridView.count(
                        crossAxisCount: larguraEcra < 600 ? 1 : (larguraEcra < 1100 ? 2 : 4),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 2.2,
                        children: [
                          _buildKpiCard(
                            titulo: 'Encomendas Ativas',
                            valor: '$_encomendasAtivas',
                            subtitulo: 'A decorrer na fábrica',
                            corIcone: Colors.blue.shade600,
                            fundoIcone: Colors.blue.shade50,
                            icone: Icons.precision_manufacturing_outlined,
                          ),
                          _buildKpiCard(
                            titulo: 'Encomendas Atrasadas',
                            valor: '$_encomendasAtrasadas',
                            subtitulo: 'Prazo de entrega expirado',
                            corIcone: Colors.red.shade600,
                            fundoIcone: Colors.red.shade50,
                            icone: Icons.warning_amber_rounded,
                            alerta: _encomendasAtrasadas > 0,
                          ),
                          _buildKpiCard(
                            titulo: 'Concluídas Hoje',
                            valor: '$_concluidasHoje',
                            subtitulo: 'Finalizadas nas últimas 24h',
                            corIcone: Colors.green.shade600,
                            fundoIcone: Colors.green.shade50,
                            icone: Icons.check_circle_outline,
                          ),
                          _buildKpiCard(
                            titulo: 'Disponibilidade de Postos',
                            valor: '${_disponibilidadeOEE.toStringAsFixed(0)}%',
                            subtitulo: 'Métrica de OEE Industrial',
                            corIcone: Colors.deepPurple.shade600,
                            fundoIcone: Colors.deepPurple.shade50,
                            icone: Icons.bolt_outlined,
                            alerta: _disponibilidadeOEE < 90,
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
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ligação ao Chão de Fábrica Ativa',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
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

  Widget _buildKpiCard({
    required String titulo,
    required String valor,
    required String subtitulo,
    required Color corIcone,
    required Color fundoIcone,
    required IconData icone,
    bool alerta = false,
  }) {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: alerta ? Colors.red.shade200 : Colors.grey.shade200, 
          width: alerta ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    valor,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: fundoIcone,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, color: corIcone, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    final int valorMaximo = _fasesDistribuicao.values.fold(0, (max, e) => e > max ? e : max);
    final double alturaGrafico = 250.0;

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribuição por Fase de Produção',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Quantidade de encomendas atualmente ativas em cada etapa',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.blue.shade400,
                                  Colors.blue.shade600,
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
                          Text(
                            fase,
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
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
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                if (_alertasIncidencias.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_alertasIncidencias.length} Paragens',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Paragens registadas no chão de fábrica',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
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
            Icon(Icons.gpp_good_outlined, size: 48, color: Colors.green),
            SizedBox(height: 12),
            Text(
              'Chão de Fábrica a 100%!',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            Text(
              'Sem paragens ou bloqueios reportados.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
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
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 20),
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
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ATENÇÃO',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Posto: ${dados.posto}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  inc['motivo'] ?? 'Sem motivo indicado.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '⏱️ Ativo: ${_calcularTempoDowntime(inc['created_at'] ?? DateTime.now().toIso8601String())}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Op: ${dados.operador}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
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