import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';
import '../login_screen.dart';
import 'criar_encomenda_screen.dart';
import 'gestao_utilizadores_screen.dart'; // Import da página de aprovação

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({super.key});

  @override
  State<PainelControloScreen> createState() => _PainelControloScreenState();
}

class _PainelControloScreenState extends State<PainelControloScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _encomendas = [];
  bool _isLoading = true;

  int _ativasCount = 0;
  int _concluidasCount = 0;

  @override
  void initState() {
    super.initState();
    _carregarDadosDashboard();
  }

  Future<void> _carregarDadosDashboard() async {
    try {
      final data = await _supabase
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega, fase_atual_id');

      setState(() {
        _encomendas = data;
        _ativasCount = data.where((e) => e['fase_atual_id'] != null).length;
        _concluidasCount = data.where((e) => e['fase_atual_id'] == null).length;
        _isLoading = false;
      });
    } catch (error) {
      print('Erro ao carregar dados do dashboard: $error');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Administrativo'),
        backgroundColor: Colors.deepPurple.shade50,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _carregarDadosDashboard();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Visão Geral do Sistema',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // 1. Cartões de Métricas
                  Row(
                    children: [
                      Expanded(
                        child: _construirCardMetrica(
                          titulo: 'Encomendas Ativas',
                          valor: '$_ativasCount',
                          cor: TemasCores.laranjaAlerta,
                          icone: Icons.pending_actions,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _construirCardMetrica(
                          titulo: 'Concluídas hoje',
                          valor: '$_concluidasCount',
                          cor: TemasCores.verdeSucesso,
                          icone: Icons.check_circle_outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 2. NOVA SECÇÃO DE ACÇÕES RÁPIDAS (Garante visibilidade total)
                  const Text(
                    'Ferramentas de Gestão',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.deepPurple.shade50.withOpacity(0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => const GestaoUtilizadoresScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TemasCores.primariaRoxa,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.people, size: 20),
                            label: const Text(
                              'Gestão de Utilizadores (Aprovações)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 3. Listagem de Encomendas
                  const Text(
                    'Ordens de Fabrico em Curso',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  _encomendas.isEmpty
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(child: Text('Nenhuma encomenda encontrada.')),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _encomendas.length,
                          itemBuilder: (context, index) {
                            final encomenda = _encomendas[index];
                            final isConcluida = encomenda['fase_atual_id'] == null;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(
                                  Icons.inventory,
                                  color: isConcluida ? Colors.green : Colors.blue,
                                ),
                                title: Text('Código: ${encomenda['codigo_rastreio']}'),
                                subtitle: Text('Entrega prevista: ${encomenda['data_entrega']}'),
                                trailing: Chip(
                                  label: Text(isConcluida ? 'Concluída' : 'Em Curso'),
                                  backgroundColor: isConcluida ? Colors.green.shade50 : Colors.orange.shade50,
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: TemasCores.primariaRoxa,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CriarEncomendaScreen()),
          );
          if (result == true) {
            setState(() => _isLoading = true);
            _carregarDadosDashboard();
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _construirCardMetrica({
    required String titulo,
    required String valor,
    required Color cor,
    required IconData icone,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cor.withOpacity(0.1),
              child: Icon(icone, color: cor),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.grey, fontSize: 14)),
                Text(
                  valor,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}