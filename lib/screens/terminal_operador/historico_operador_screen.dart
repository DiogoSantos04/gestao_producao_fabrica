import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoOperadorScreen extends StatefulWidget {
  const HistoricoOperadorScreen({super.key});

  @override
  State<HistoricoOperadorScreen> createState() => _HistoricoOperadorScreenState();
}

class _HistoricoOperadorScreenState extends State<HistoricoOperadorScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  
  List<dynamic> _historicoCompleto = [];
  List<dynamic> _historicoFiltrado = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
    _searchController.addListener(_filtrarResultados);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Consulta relacional que também busca os registos de incidências associados
  Future<void> _carregarHistorico() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('historico_producao')
          .select('''
            id,
            data_conclusao,
            encomendas!encomenda_id (
              codigo_rastreio,
              tipos_produto!tipos_produtos_id (
                nome_tipo_produto
              )
            ),
            fases_padrao!fase_concluida_id (
              nome_fase_padrao
            ),
            incidencias (
              id,
              motivo
            )
          ''')
          .eq('utilizador_id', user.id)
          .order('data_conclusao', ascending: false);

      if (mounted) {
        setState(() {
          _historicoCompleto = data;
          _historicoFiltrado = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico de produção: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filtrarResultados() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _historicoFiltrado = _historicoCompleto;
      } else {
        _historicoFiltrado = _historicoCompleto.where((registo) {
          final codigo = registo['encomendas']?['codigo_rastreio']?.toString().toLowerCase() ?? '';
          return codigo.contains(query);
        }).toList();
      }
    });
  }

  String _formatarData(String? isoString) {
    if (isoString == null) return '-';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '-';
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final ano = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano $hora:$minuto';
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
                  const Text(
                    'Histórico de Produção',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Consulte suas tarefas concluídas ou bloqueios registados',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 32),

                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Pesquisar por ID...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          border: InputBorder.none,
                          icon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

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
                        child: Column(
                          children: [
                            // Cabeçalho da Tabela
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'ID da Encomenda',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      'Produto',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3, // Aumentado ligeiramente para caber o motivo
                                    child: Text(
                                      'Ação / Fase',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      'Data/Hora',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'Estado',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            Expanded(
                              child: _historicoFiltrado.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Nenhum registo de produção encontrado.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _historicoFiltrado.length,
                                      itemBuilder: (context, index) {
                                        final item = _historicoFiltrado[index];
                                        final codigo = item['encomendas']?['codigo_rastreio'] ?? 'N/A';
                                        final produto = item['encomendas']?['tipos_produto']?['nome_tipo_produto'] ?? 'N/A';
                                        final fase = item['fases_padrao']?['nome_fase_padrao'] ?? 'N/A';
                                        final dataConclusao = _formatarData(item['data_conclusao']);

                                        // Determinar se este registo de histórico é um bloqueio
                                        final List<dynamic> incidencias = item['incidencias'] ?? [];
                                        final bool isBloqueado = incidencias.isNotEmpty;
                                        final String? motivoBloqueio = isBloqueado ? incidencias.first['motivo'] : null;

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  codigo,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  produto,
                                                  style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                                                ),
                                              ),
                                              // Coluna Ação / Fase (Com aviso de bloqueio em subtexto se aplicável)
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      fase,
                                                      style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                                                    ),
                                                    if (isBloqueado && motivoBloqueio != null) ...[
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                                                          const SizedBox(width: 4),
                                                          Expanded(
                                                            child: Text(
                                                              motivoBloqueio,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 11, 
                                                                color: Colors.red, 
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ]
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  dataConclusao,
                                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                                ),
                                              ),
                                              // Badge de Estado Dinâmico (Concluído vs Bloqueado)
                                              Expanded(
                                                flex: 1,
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: isBloqueado 
                                                          ? const Color(0xFFFEE2E2) // Vermelho suave
                                                          : const Color(0xFFD1FAE5), // Verde suave
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      isBloqueado ? 'Bloqueado' : 'Concluído',
                                                      style: TextStyle(
                                                        color: isBloqueado 
                                                            ? const Color(0xFF991B1B) // Vermelho escuro
                                                            : const Color(0xFF065F46), // Verde escuro
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
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