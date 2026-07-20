import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';

// Importa os ecrãs desenvolvidos
import 'dashboard_principal_screen.dart';
import 'gestao_utilizadores_screen.dart';
import 'criar_encomenda_screen.dart'; 
import 'painel_controlo_screen.dart'; 
import 'gestao_fluxos_screen.dart';
import 'informacoes_clientes_screen.dart'; 
import 'relatorios_admin_screen.dart'; // 👈 1. Import do teu novo ecrã de relatórios ativado!

class DashboardAdminShell extends StatefulWidget {
  const DashboardAdminShell({super.key});

  @override
  State<DashboardAdminShell> createState() => _DashboardAdminShellState();
}

class _DashboardAdminShellState extends State<DashboardAdminShell> {
  final AuthService _authService = AuthService();
  int _indiceAtual = 0;

  // Lista dos menus correspondente às opções da barra lateral
  final List<Map<String, dynamic>> _menuItens = [
    {'titulo': 'Dashboard', 'icone': Icons.dashboard_outlined},
    {'titulo': 'Fluxos Produtivos', 'icone': Icons.schema_outlined},
    {'titulo': 'Utilizadores', 'icone': Icons.people_alt_outlined},
    {'titulo': 'Planeamento', 'icone': Icons.assignment_outlined},
    {'titulo': 'Ordens em Curso', 'icone': Icons.precision_manufacturing_outlined},
    {'titulo': 'Clientes', 'icone': Icons.business_center_outlined},
    {'titulo': 'Relatórios', 'icone': Icons.analytics_outlined},
  ];

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    // Lista de ecrãs que serão renderizados à direita
    final List<Widget> _telas = [
      const DashboardPrincipalScreen(),
      const GestaoFluxosScreen(), 
      const GestaoUtilizadoresScreen(),
      const CriarEncomendaScreen(),
      const PainelControloScreen(),
      const ClientesScreen(),
      const RelatoriosAdminScreen(), // 👈 2. Ativado! Substituído o Placeholder pelo ecrã real de Relatórios e Feedback
    ];

    return Scaffold(
      appBar: !eDesktop
          ? AppBar(
              title: Text(_menuItens[_indiceAtual]['titulo']),
              backgroundColor: Colors.deepPurple.shade50,
            )
          : null,
      drawer: !eDesktop ? Drawer(child: _buildSidebar(dentroDrawer: true)) : null,
      body: Row(
        children: [
          // Se for ecrã grande (Desktop/Web), mostra a Sidebar fixa do lado esquerdo
          if (eDesktop)
            SizedBox(
              width: 260,
              child: _buildSidebar(dentroDrawer: false),
            ),
          
          // Área de Conteúdo Principal (Lado Direito)
          Expanded(
            child: IndexedStack(
              index: _indiceAtual,
              children: _telas,
            ),
          ),
        ],
      ),
    );
  }

  // --- CONSTRUTOR DA SIDEBAR ---
  Widget _buildSidebar({required bool dentroDrawer}) {
    return Container(
      color: const Color(0xFF111625), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header da Sidebar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: const Row(
              children: [
                Icon(Icons.settings_suggest_rounded, color: Colors.blue, size: 28),
                SizedBox(width: 12),
                Text(
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
          
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 16),

          // Lista de Opções do Menu
          Expanded(
            child: ListView.builder(
              itemCount: _menuItens.length,
              itemBuilder: (context, index) {
                final item = _menuItens[index];
                final bool estaSelecionado = _indiceAtual == index;

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
                        _indiceAtual = index;
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

          // Rodapé com o Logout e Info do Utilizador
          const Divider(color: Colors.white10, height: 1),
          _buildRodapeSidebar(),
        ],
      ),
    );
  }

  // --- SECÇÃO DE LOGOUT / PERFIL ---
  Widget _buildRodapeSidebar() {
    final user = _authService.utilizadorAtual;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                radius: 18,
                child: const Text(
                  'AD',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.nomeUtilizador ?? 'Administrador',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      user?.email ?? 'admin@factory.com',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _efetuarLogout,
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

  Future<void> _efetuarLogout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}

// --- CLASSE AUXILIAR PARA ECRÃS EM DESENVOLVIMENTO (PLACEHOLDER) ---
class PlaceholderScreen extends StatelessWidget {
  final String titulo;
  final IconData icone;

  const PlaceholderScreen({super.key, required this.titulo, required this.icone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Módulo de $titulo',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este ecrã está planeado e encontra-se em fase de desenvolvimento.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}