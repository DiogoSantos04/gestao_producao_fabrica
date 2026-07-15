import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class DashboardPrincipalScreen extends StatefulWidget {
  const DashboardPrincipalScreen({super.key});

  @override
  State<DashboardPrincipalScreen> createState() => _DashboardPrincipalScreenState();
}

class _DashboardPrincipalScreenState extends State<DashboardPrincipalScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Real-time channel para escutar alterações na fábrica
  RealtimeChannel? _factorySubscription;
  Timer? _everySecondTimer;

  bool _isLoading = true;

  // KPIs de Produção & Fabrico.io Metrics
  int _encomendasAtivas = 0;
  int _encomendasAtrasadas = 0;
  int _concluidasHoje = 0;
  double _disponibilidadeOEE = 100.0; // % de postos sem paragens ativas

  // Distribuição de Encomendas por Fase de Produção (Dados do Gráfico)
  Map<String, int> _fasesDistribuicao = {
    'Corte': 0,
    'Montagem': 0,
    'Acabamento': 0,
    'Controlo': 0,
    'Embalagem': 0,
  };

  // Alertas de Incidência Ativos (Downtime Tickets à la Fabrico.io)
  List<Map<String, dynamic>> _alertasIncidencias = [];

  @override
  void initState() {
    super.initState();
    _carregarDadosDashboard();
    _inicializarSubscricaoTempoReal();
    
    // Timer para atualizar o contador de tempo de downtime decorrido nos alertas
    _everySecondTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _everySecondTimer?.cancel();
    if (_factorySubscription != null) {
      _supabase.removeChannel(_factorySubscription!);
    }
    super.dispose();
  }

  /// ⚡ Liga o canal de escuta em tempo real às tabelas de encomendas e incidências do Supabase
  void _inicializarSubscricaoTempoReal() {
    _factorySubscription = _supabase.channel('db-factory-changes')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'encomendas',
        callback: (payload) {
          print('⚡ [Realtime] Encomendas atualizadas! Atualizando Dashboard...');
          _carregarDadosDashboard();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'incidencias',
        callback: (payload) {
          print('⚡ [Realtime] Incidências reportadas! Atualizando Dashboard...');
          _carregarDadosDashboard();
        },
      );

    _factorySubscription?.subscribe();
  }

  /// Carrega e calcula todas as métricas necessárias para o painel de controlo
  Future<void> _carregarDadosDashboard() async {
    try {
      if (!mounted) return;

      // 1. Procurar Encomendas do Sistema
      final List<dynamic> encomendas = await _supabase
          .from('encomendas')
          .select();

      // 2. Procurar Incidências Ativas (Falta de material, avaria, etc.)
      final List<dynamic> incidenciasAtivas = await _supabase
          .from('incidencias')
          .select()
          .eq('resolvida', false); // Filtrar apenas as não resolvidas

      if (!mounted) return;

      int ativas = 0;
      int atrasadas = 0;
      int concluidasHoje = 0;
      
      Map<String, int> tempFases = {
        'Corte': 0,
        'Montagem': 0,
        'Acabamento': 0,
        'Controlo': 0,
        'Embalagem': 0,
      };

      final DateTime hoje = DateTime.now();

      for (var enc in encomendas) {
        final String estado = enc['estado'] ?? 'Inativo';
        final String faseAtual = enc['fase_atual'] ?? '';
        final String? prazoStr = enc['data_entrega'];
        
        if (estado == 'Concluida') {
          // Simplificação: Verifica se foi concluído hoje (comparando data de update)
          final DateTime updatedAt = DateTime.parse(enc['updated_at'] ?? hoje.toIso8601String());
          if (updatedAt.day == hoje.day && updatedAt.month == hoje.month && updatedAt.year == hoje.year) {
            concluidasHoje++;
          }
        } else if (estado == 'Ativo') {
          ativas++;
          
          // Agrupa para o Gráfico de Barras Dinâmico
          if (tempFases.containsKey(faseAtual)) {
            tempFases[faseAtual] = (tempFases[faseAtual] ?? 0) + 1;
          }

          // Verifica se está atrasada (prazo expirado)
          if (prazoStr != null) {
            final DateTime prazo = DateTime.parse(prazoStr);
            if (prazo.isBefore(hoje)) {
              atrasadas++;
            }
          }
        }
      }

      // Cálculo de Disponibilidade de Máquinas (Métrica Fabrico.io)
      // Se tivermos 5 postos principais ativos e 1 está parado por incidência ativa, disponibilidade = 80%
      final int totalPostos = 5;
      final int postosBloqueados = incidenciasAtivas.map((e) => e['posto_trabalho']).toSet().length;
      final double disponibilidade = ((totalPostos - postosBloqueados) / totalPostos) * 100;

      setState(() {
        _encomendasAtivas = ativas;
        _encomendasAtrasadas = atrasadas;
        _concluidasHoje = concluidasHoje;
        _disponibilidadeOEE = disponibilidade < 0 ? 0 : disponibilidade;
        _fasesDistribuicao = tempFases;
        _alertasIncidencias = List<Map<String, dynamic>>.from(incidenciasAtivas);
        _isLoading = false;
      });

    } catch (e) {
      print('❌ Erro ao processar dados do dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Calcula há quanto tempo uma paragem/incidência está ativa no chão de fábrica
  String _calcularTempoDowntime(String dataCriacaoStr) {
    final DateTime dataCriacao = DateTime.parse(dataCriacaoStr);
    final Duration diferenca = DateTime.now().difference(dataCriacao);

    if (diferenca.inMinutes < 60) {
      return '${diferenca.inMinutes}m atrás';
    } else if (diferenca.inHours < 24) {
      return '${diferenca.inHours}h ${diferenca.inMinutes % 60}m atrás';
    } else {
      return '${diferenca.inDays} dias atrás';
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
                  // --- TOP HEADER BAR ---
                  _buildHeader(),

                  const SizedBox(height: 24),

                  // --- METRIC CARDS (ROW) ---
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
                            subtitulo: '+12% vs. mês anterior',
                            corIcone: Colors.blue.shade600,
                            fundoIcone: Colors.blue.shade50,
                            icone: Icons.precision_manufacturing_outlined,
                          ),
                          _buildKpiCard(
                            titulo: 'Encomendas Atrasadas',
                            valor: '$_encomendasAtrasadas',
                            subtitulo: '-25% vs. mês anterior',
                            corIcone: Colors.red.shade600,
                            fundoIcone: Colors.red.shade50,
                            icone: Icons.warning_amber_rounded,
                            alerta: _encomendasAtrasadas > 0,
                          ),
                          _buildKpiCard(
                            titulo: 'Concluídas Hoje',
                            valor: '$_concluidasHoje',
                            subtitulo: '+33% vs. ontem',
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

                  // --- MAIN SECTIONS (CHART & INCIDENTS) ---
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

  // --- HEADER WIDGET ---
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

  // --- KPI CARD WIDGET ---
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
        side: BorderSide(color: alerta ? Colors.red.shade200 : Colors.grey.shade200, width: alerta ? 1.5 : 1),
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

  // --- CHART CARD (DISTRIBUIÇÃO DE FASES) ---
  Widget _buildChartCard() {
    // Descobrir o valor máximo para poder escalar a altura das barras de forma dinâmica
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
              'Quantidade de encomendas ativas em cada posto',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            
            // Área de renderização do gráfico de barras
            SizedBox(
              height: alturaGrafico,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _fasesDistribuicao.entries.map((entry) {
                  final String fase = entry.key;
                  final int quantidade = entry.value;

                  // Calcula a altura da barra em percentagem face ao máximo de encomendas
                  final double percentagemAltura = valorMaximo == 0 ? 0.05 : (quantidade / valorMaximo);

                  return Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Tooltip / Contador por cima da barra
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 300),
                          opacity: quantidade > 0 ? 1.0 : 0.4,
                          child: Text(
                            '$quantidade',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // A Barra Animada propriamente dita
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutBack,
                          width: 32,
                          height: (alturaGrafico - 40) * percentagemAltura,
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
                              topLeft: Radius.circular(6),
                              topRight: Radius.circular(6),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Rótulo da Fase no eixo X
                        Text(
                          fase,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                        ),
                      ],
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

  // --- ALERTAS DE INCIDÊNCIA (ESTILO FABRICO.IO) ---
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

            // Lista de Incidências
            _alertasIncidencias.isEmpty
                ? const SizedBox(
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
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _alertasIncidencias.length,
                    itemBuilder: (context, index) {
                      final inc = _alertasIncidencias[index];
                      final String criticidade = inc['criticidade'] ?? 'Média';
                      final bool eCritico = criticidade.toLowerCase() == 'alta' || criticidade.toLowerCase() == 'urgente';

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
                            Icon(
                              Icons.error_outline_rounded, 
                              color: eCritico ? Colors.red.shade600 : Colors.orange.shade600,
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
                                      Text(
                                        'Enc. #${inc['encomenda_id'] ?? 'N/A'}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: eCritico ? Colors.red.shade100 : Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          criticidade.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9, 
                                            fontWeight: FontWeight.bold,
                                            color: eCritico ? Colors.red.shade700 : Colors.orange.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Posto: ${inc['posto_trabalho'] ?? 'Não especificado'}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black54),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    inc['descricao'] ?? 'Sem descrição fornecida.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '⏱️ Downtime: ${_calcularTempoDowntime(inc['created_at'] ?? DateTime.now().toIso8601String())}',
                                        style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Operador ID: #${inc['operador_id'] ?? '?'}',
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
                    },
                  ),
          ],
        ),
      ),
    );
  }
}