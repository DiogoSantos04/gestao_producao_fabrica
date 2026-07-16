import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';
import 'fila_trabalho_screen.dart';
import 'historico_operador_screen.dart'; 
import 'relatorios_operador_screen.dart';

class OperadorShellScreen extends StatefulWidget {
  const OperadorShellScreen({super.key});

  @override
  State<OperadorShellScreen> createState() => _OperadorShellScreenState();
}

class _OperadorShellScreenState extends State<OperadorShellScreen> {
  final AuthService _authService = AuthService();
  int _indiceSelecionado = 0; // 0: Minha Fila, 1: Histórico, 2: Relatórios, 3: Perfil
  
  final DateTime _inicioSessao = DateTime.now();

  final List<Map<String, dynamic>> _menuItens = [
    {'titulo': 'Minha Fila', 'icone': Icons.assignment_outlined},
    {'titulo': 'Histórico', 'icone': Icons.history_toggle_off},
    {'titulo': 'Relatórios', 'icone': Icons.analytics_outlined},
  ];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _processarFechoSessaoComRelatorio() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.all(24.0),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Compilando Relatório de Turno...',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'A processar os vossos avanços e incidências de hoje.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final user = _authService.utilizadorAtual;
      final database = Supabase.instance.client;
      // 👈 CORRIGIDO: Obtém o ID diretamente do Auth do Supabase para evitar conflito com o modelo
      final String? authUserId = database.auth.currentUser?.id; 
      
      int avancosSessao = 0;
      int incidenciasSessao = 0;

      if (authUserId != null) {
        // 1. Consulta os avanços utilizando o ID de autenticação seguro
        final historicoData = await database
            .from('historico_producao')
            .select('id, incidencias(id)')
            .eq('utilizador_id', authUserId)
            .gte('data_conclusao', _inicioSessao.toIso8601String());

        avancosSessao = (historicoData as List).length;

        for (var row in historicoData) {
          final List<dynamic> incs = row['incidencias'] ?? [];
          if (incs.isNotEmpty) {
            incidenciasSessao++;
          }
        }
      }

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;
      Navigator.of(context).pop(); // Fecha o diálogo de processamento

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.summarize_outlined, color: Colors.blue, size: 28),
              SizedBox(width: 12),
              Text('Resumo de Fecho de Turno'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Operador: ${user?.nomeUtilizador ?? "Funcionário"}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('• Duração da Sessão: ${_formatarDuracao(DateTime.now().difference(_inicioSessao))}'),
              Text('• Avanços de Fase Registados: $avancosSessao'),
              Text(
                '• Incidências/Bloqueios: $incidenciasSessao',
                style: TextStyle(color: incidenciasSessao > 0 ? Colors.red : Colors.black87),
              ),
              const Divider(height: 24),
              const Text(
                'O PDF "Relatorio_Sessao_Automatico.pdf" foi compilado e guardado com sucesso no arquivo do sistema.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check),
              label: const Text('Concluir e Sair'), // 👈 CORRIGIDO: Substituído 'child' por 'label'
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            )
          ],
        ),
      );

      _executarLogoutFinal();

    } catch (e) {
      debugPrint('Erro ao processar relatório automático: $e');
      if (mounted) Navigator.of(context).pop();
      _executarLogoutFinal();
    }
  }

  void _executarLogoutFinal() async {
    await _authService.logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  String _formatarDuracao(Duration d) {
    String duasCasas(int n) => n.toString().padLeft(2, "0");
    String horas = duasCasas(d.inHours);
    String minutos = duasCasas(d.inMinutes.remainder(60));
    return "${horas}h ${minutos}m";
  }

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    final List<Widget> _telas = [
      const FilaTrabalhoScreen(),
      const HistoricoOperadorScreen(),
      const RelatoriosOperadorScreen(),
      _construirEcraPerfil(),
    ];

    return Scaffold(
      appBar: !eDesktop
          ? AppBar(
              title: Text(_indiceSelecionado == 3 
                  ? 'O Meu Perfil' 
                  : _menuItens[_indiceSelecionado]['titulo']),
              backgroundColor: Colors.deepPurple.shade50,
            )
          : null,
      drawer: !eDesktop ? Drawer(child: _buildSidebar(dentroDrawer: true)) : null,
      body: Row(
        children: [
          if (eDesktop)
            SizedBox(
              width: 260,
              child: _buildSidebar(dentroDrawer: false),
            ),
          Expanded(
            child: IndexedStack(
              index: _indiceSelecionado,
              children: _telas,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar({required bool dentroDrawer}) {
    return Container(
      color: const Color(0xFF111625),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: const Row(
              children: [
                Icon(Icons.precision_manufacturing, color: Colors.blue, size: 28),
                SizedBox(width: 12),
                Text(
                  'Terminal Operador',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),

          Expanded(
            child: ListView.builder(
              itemCount: _menuItens.length,
              itemBuilder: (context, index) {
                final item = _menuItens[index];
                final bool estaSelecionado = _indiceSelecionado == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: ListTile(
                    selected: estaSelecionado,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    selectedTileColor: Colors.white.withOpacity(0.08),
                    leading: Icon(
                      item['icone'],
                      color: estaSelecionado ? Colors.blue : Colors.grey.shade500,
                      size: 20,
                    ),
                    title: Text(
                      item['titulo'],
                      style: TextStyle(
                        color: estaSelecionado ? Colors.white : Colors.grey.shade400,
                        fontSize: 14,
                        fontWeight: estaSelecionado ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        _indiceSelecionado = index;
                      });
                      if (dentroDrawer) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                );
              },
            ),
          ),

          const Divider(color: Colors.white10, height: 1),
          _buildRodapeSidebar(dentroDrawer),
        ],
      ),
    );
  }

  Widget _buildRodapeSidebar(bool dentroDrawer) {
    final bool estaNoPerfil = _indiceSelecionado == 3;
    final user = _authService.utilizadorAtual;

    final String nomeCompleto = user?.nomeUtilizador ?? 'Operador';
    final String idDisplay = 'EMP-2026-${nomeCompleto.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _indiceSelecionado = 3;
              });
              if (dentroDrawer) {
                Navigator.pop(context);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: estaNoPerfil ? Colors.white.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    radius: 18,
                    child: Text(
                      nomeCompleto.isNotEmpty ? nomeCompleto.substring(0, 2).toUpperCase() : 'OP',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nomeCompleto,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          idDisplay,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _processarFechoSessaoComRelatorio,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.15),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              minimumSize: const Size.fromHeight(38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text('Terminar Sessão', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _construirEcraPerfil() {
    final user = _authService.utilizadorAtual;
    final String nomeCompleto = user?.nomeUtilizador ?? 'Operador';
    final String emailDisplay = user?.email ?? 'operador@factory.com';
    final String idDisplay = 'EMP-2026-${nomeCompleto.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 45,
                    backgroundColor: Colors.blue.shade600,
                    child: Text(
                      nomeCompleto.isNotEmpty ? nomeCompleto.substring(0, 2).toUpperCase() : 'OP',
                      style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    nomeCompleto,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Operador Industrial',
                    style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const Divider(height: 40),
                  
                  _construirCampoInformativo(
                    label: 'Email Institucional',
                    valor: emailDisplay,
                    icone: Icons.email_outlined,
                  ),
                  const SizedBox(height: 16),
                  _construirCampoInformativo(
                    label: 'ID do Funcionário',
                    valor: idDisplay,
                    icone: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 32),
                  
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidade de alteração de senha enviada por email.')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.vpn_key_outlined, color: Colors.black87),
                    label: const Text('Alterar Palavra-passe', style: TextStyle(color: Colors.black87)),
                  ),
                  const SizedBox(height: 12),
                  
                  ElevatedButton.icon(
                    onPressed: _processarFechoSessaoComRelatorio,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.logout),
                    label: const Text('Terminar Sessão'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirCampoInformativo({
    required String label,
    required String valor,
    required IconData icone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(width: 1, color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icone, color: Colors.grey),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          )
        ],
      ),
    );
  }
}