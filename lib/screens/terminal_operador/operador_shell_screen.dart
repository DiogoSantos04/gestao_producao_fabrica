import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';
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
  final _supabase = Supabase.instance.client;
  int _indiceSelecionado = 0; // 0: Minha Fila, 1: Histórico, 2: Relatórios, 3: Perfil
  
  String _nomeOperador = 'Carregando...';
  String _emailOperador = '...';
  String _idOperador = 'EMP-2026-000';
  bool _isLoadingPerfil = true;

  @override
  void initState() {
    super.initState();
    _buscarDadosOperador();
  }

  Future<void> _buscarDadosOperador() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final data = await _supabase
            .from('utilizadores')
            .select('nome_utilizador, email, utilizador_id')
            .eq('utilizador_id', user.id)
            .maybeSingle();

        if (data != null && mounted) {
          setState(() {
            _nomeOperador = data['nome_utilizador'] ?? 'Sem Nome';
            _emailOperador = data['email'] ?? user.email ?? 'Sem Email';
            _idOperador = 'EMP-2026-${data['utilizador_id'].toString().substring(0, 4).toUpperCase()}';
            _isLoadingPerfil = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao obter dados do operador: $e');
      if (mounted) {
        setState(() => _isLoadingPerfil = false);
      }
    }
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ==========================================
          // SIDEBAR (MENU LATERAL)
          // ==========================================
          Container(
            width: 260,
            color: const Color(0xFF111625),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                  child: Row(
                    children: [
                      Icon(Icons.precision_manufacturing, color: Colors.blue.shade300, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        'Sistema Industrial',
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
                _construirItemMenu(
                  indice: 0,
                  icone: Icons.assignment_outlined,
                  titulo: 'Minha Fila',
                ),
                _construirItemMenu(
                  indice: 1,
                  icone: Icons.history_toggle_off,
                  titulo: 'Histórico',
                ),
                _construirItemMenu(
                  indice: 2,
                  icone: Icons.analytics_outlined,
                  titulo: 'Relatórios',
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: InkWell(
                    onTap: () {
                      setState(() => _indiceSelecionado = 3);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: _indiceSelecionado == 3 
                            ? Colors.white.withOpacity(0.08) 
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white24,
                            child: Icon(Icons.person, color: Colors.blue.shade300),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _nomeOperador,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _idOperador,
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
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
          
          // ==========================================
          // ÁREA DE CONTEÚDO PRINCIPAL
          // ==========================================
          Expanded(
            child: Container(
              color: const Color(0xFFF8FAFC),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _obterEcraSelecionado(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirItemMenu({
    required int indice,
    required IconData icone,
    required String titulo,
  }) {
    final isSelecionado = _indiceSelecionado == indice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: InkWell(
        onTap: () => setState(() => _indiceSelecionado = indice),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          decoration: BoxDecoration(
            color: isSelecionado ? Colors.blue.shade700 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                icone,
                color: isSelecionado ? Colors.white : Colors.grey.shade400,
                size: 20,
              ),
              const SizedBox(width: 16),
              Text(
                titulo,
                style: TextStyle(
                  color: isSelecionado ? Colors.white : Colors.grey.shade300,
                  fontWeight: isSelecionado ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _obterEcraSelecionado() {
    switch (_indiceSelecionado) {
      case 0:
        return const FilaTrabalhoScreen(); 
      case 1:
        return const HistoricoOperadorScreen();
      case 2:
        return const RelatoriosOperadorScreen();
      case 3:
        return _construirEcraPerfil();
      default:
        return const Center(child: Text('Ecrã não encontrado'));
    }
  }

  // ==========================================
  // ECRÃ DO PERFIL (Figura 35)
  // ==========================================
  Widget _construirEcraPerfil() {
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
                      _nomeOperador.isNotEmpty ? _nomeOperador.substring(0, 2).toUpperCase() : 'OP',
                      style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _nomeOperador,
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
                    valor: _emailOperador,
                    icone: Icons.email_outlined,
                  ),
                  const SizedBox(height: 16),
                  _construirCampoInformativo(
                    label: 'ID do Funcionário',
                    valor: _idOperador,
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
                    icon: const Icon(Icons.vpn_key_outlined, color: Colors.black87), // CORRIGIDO: Colors.black87
                    label: const Text('Alterar Palavra-passe', style: TextStyle(color: Colors.black87)), // CORRIGIDO: Colors.black87
                  ),
                  const SizedBox(height: 12),
                  
                  ElevatedButton.icon(
                    onPressed: _logout,
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
        border: Border.all(width: 1, color: Colors.grey.shade200), // CORRIGIDO: Border.all
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