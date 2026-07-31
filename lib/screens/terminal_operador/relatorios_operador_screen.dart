import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/pdf_service.dart'; // 👈 Import centralizado do gerador de PDF real

class RelatoriosOperadorScreen extends StatefulWidget {
  const RelatoriosOperadorScreen({super.key});

  @override
  State<RelatoriosOperadorScreen> createState() => _RelatoriosOperadorScreenState();
}

class _RelatoriosOperadorScreenState extends State<RelatoriosOperadorScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  int _totalFasesMes = 0;
  int _totalIncidenciasMes = 0;
  
  // Lista alimentada exclusivamente por dados dinâmicos da base de dados
  List<Map<String, dynamic>> _relatoriosReais = [];

  @override
  void initState() {
    super.initState();
    _processarRelatoriosReais();
  }

  Future<void> _processarRelatoriosReais() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        // Sem sessão não há nada a carregar, mas o `return` seco deixava
        // `_isLoading = true` para sempre: o ecrã ficava num spinner infinito.
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final inicioMes = DateTime(DateTime.now().year, DateTime.now().month, 1);
      
      // Consulta todo o histórico real do operador ordenado de forma cronológica decrescente
      final dadosProducao = await _supabase
          .from('historico_producao')
          .select('id, data_conclusao, incidencias(id)')
          .eq('utilizador_id', user.id)
          .order('data_conclusao', ascending: false);

      int fasesMes = 0;
      int incsMes = 0;
      
      // Estrutura auxiliar para agrupar as ações por dia de calendário (turno único diário)
      final Map<String, Map<String, dynamic>> turnosAgrupados = {};

      for (var row in dadosProducao) {
        final String? dataStr = row['data_conclusao'];
        if (dataStr == null) continue;
        
        // `data_conclusao` é `timestamptz` e chega em UTC. Sem `toLocal()` o
        // agrupamento por dia de turno e a comparação com `inicioMes` (que é
        // hora local) misturavam fusos, deslocando registos de fim de turno
        // para o dia seguinte.
        final DateTime data = DateTime.parse(dataStr).toLocal();
        final String chaveDia = '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
        final String dataFormatada = '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
        
        final List<dynamic> listaIncidencias = row['incidencias'] ?? [];
        final bool temIncidencia = listaIncidencias.isNotEmpty;

        // Filtra métricas específicas acumuladas do mês corrente.
        // `!isBefore` e não `isAfter`: `inicioMes` é o dia 1 às 00:00, pelo que
        // `isAfter` excluía o trabalho registado exatamente nesse instante.
        if (!data.isBefore(inicioMes)) {
          fasesMes++;
          if (temIncidencia) incsMes++;
        }

        // Agrupa as ações dinamicamente no turno correspondente ao dia
        if (!turnosAgrupados.containsKey(chaveDia)) {
          turnosAgrupados[chaveDia] = {
            'nome': 'Relatorio_Turno_${data.day.toString().padLeft(2, '0')}${data.month.toString().padLeft(2, '0')}${data.year}.pdf',
            'data': dataFormatada,
            'fases': 1,
            'incidencias': temIncidencia ? 1 : 0,
          };
        } else {
          turnosAgrupados[chaveDia]!['fases'] += 1;
          if (temIncidencia) {
            turnosAgrupados[chaveDia]!['incidencias'] += 1;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _totalFasesMes = fasesMes;
        _totalIncidenciasMes = incsMes;
        _relatoriosReais = turnosAgrupados.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao processar relatórios dinâmicos: $e');
      if (mounted) setState(() => _isLoading = false);
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
                  // Cabeçalho adaptado da Figura 34 do mockup do projeto
                  const Text(
                    'Área de Relatórios',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Consulte o histórico de turnos e descarregue os relatórios automáticos da sua atividade',
                    style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 32),

                  // Painel Superior de Indicadores Acumulados (Mês Corrente)
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Métricas de Produção Acumuladas (Mês Corrente)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              // Totalizador de Fases Concluídas
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0FDF4),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFDCFCE7)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 24),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Fases Superadas', style: TextStyle(fontSize: 11, color: Color(0xFF15803D))),
                                          Text('$_totalFasesMes etapas', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              // Totalizador de Incidências do Mês
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFEE2E2)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Bloqueios Sinalizados', style: TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
                                          Text('$_totalIncidenciasMes alertas', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  const Text(
                    'Relatórios de Turno Disponíveis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 12),

                  // Lista Inferior de Ficheiros Reais para Gravação (Figura 34)
                  Expanded(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      color: Colors.white,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _relatoriosReais.isEmpty
                            ? const Center(
                                child: Text(
                                  'Ainda não existem turnos registados com atividade nesta conta.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _relatoriosReais.length,
                                separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                                itemBuilder: (context, index) {
                                  final item = _relatoriosReais[index];
                                  final int qtdFases = item['fases'];
                                  final int qtdIncs = item['incidencias'];

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.blue, size: 24),
                                    ),
                                    title: Text(
                                      item['nome']!,
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        'Dia: ${item['data']} • Avanços: $qtdFases • Bloqueios reportados: $qtdIncs',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.download_outlined, color: Color(0xFF3B82F6)),
                                      tooltip: 'Descarregar PDF do Turno',
                                      onPressed: () async {
                                        final user = _supabase.auth.currentUser;
                                        final String nomeUser = user?.email?.split('@').first ?? 'Operador';

                                        // Dispara a compilação e download do PDF Real utilizando as métricas computadas
                                        await PdfService.descarregarRelatorioTurno(
                                          nomeOperador: nomeUser,
                                          dataTurno: item['data'],
                                          totalFases: qtdFases,
                                          totalIncidencias: qtdIncs,
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}