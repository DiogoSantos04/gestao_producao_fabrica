import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';
import '../../services/auth_service.dart';
import '../../services/pdf_service.dart';
import '../login_screen.dart';
import 'fila_trabalho_screen.dart';
import 'historico_operador_screen.dart'; 
import 'relatorios_operador_screen.dart';

class OperadorShellScreen extends StatefulWidget {
  final String? utilizadorId;

  const OperadorShellScreen({super.key, this.utilizadorId});

  @override
  State<OperadorShellScreen> createState() => _OperadorShellScreenState();
}

class _OperadorShellScreenState extends State<OperadorShellScreen> {
  final AuthService _authService = AuthService();
  final _supabase = Supabase.instance.client;

  int _indiceSelecionado = 0; // 0: Minha Fila, 1: Histórico, 2: Relatórios, 3: Perfil
  final DateTime _inicioSessao = DateTime.now();

  // Dados dinâmicos do utilizador autenticado
  String _nomeUtilizador = 'Operador';
  String _emailUtilizador = 'carregando...';
  bool _carregandoPerfil = true;

  // Subscrição em tempo real via WebSocket
  StreamSubscription<List<Map<String, dynamic>>>? _utilizadorStreamSubscription;

  final List<Map<String, dynamic>> _menuItens = [
    {'titulo': 'Minha Fila', 'icone': Icons.assignment_outlined},
    {'titulo': 'Histórico', 'icone': Icons.history_toggle_off},
    {'titulo': 'Relatórios', 'icone': Icons.analytics_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _iniciarEscutaEmTempoReal();
  }

  @override
  void dispose() {
    _utilizadorStreamSubscription?.cancel();
    super.dispose();
  }

  /// Subscreve a tabela 'utilizadores' via WebSocket para atualizações em tempo real
  void _iniciarEscutaEmTempoReal() {
    try {
      final user = _supabase.auth.currentUser;
      final String? userId = widget.utilizadorId ?? user?.id;

      if (userId == null) {
        if (mounted) setState(() => _carregandoPerfil = false);
        return;
      }

      _utilizadorStreamSubscription = _supabase
          .from('utilizadores')
          .stream(primaryKey: ['utilizador_id'])
          .eq('utilizador_id', userId)
          .listen(
            (dados) {
              if (mounted && dados.isNotEmpty) {
                final registo = dados.first;
                final String? nomeDb = registo['nome_utilizador']?.toString();
                final String? emailDb = registo['email']?.toString();

                setState(() {
                  _nomeUtilizador = (nomeDb != null && nomeDb.trim().isNotEmpty)
                      ? nomeDb
                      : 'Operador';
                  _emailUtilizador = (emailDb != null && emailDb.trim().isNotEmpty)
                      ? emailDb
                      : (user?.email ?? 'operador@factory.com');
                  _carregandoPerfil = false;
                });
              }
            },
            onError: (erro) {
              debugPrint('Erro na escuta em tempo real do operador: $erro');
              if (mounted) setState(() => _carregandoPerfil = false);
            },
          );
    } catch (e) {
      debugPrint('Erro ao iniciar stream do perfil: $e');
      if (mounted) setState(() => _carregandoPerfil = false);
    }
  }

  /// Converte o nome do utilizador em iniciais (ex: "Martim Carvalho" -> "MC")
  String _obterIniciais(String? nome) {
    if (nome == null || nome.toString().trim().isEmpty) return 'OP';
    final String limpo = nome.toString().trim();
    final partes = limpo.split(' ');
    if (partes.length >= 2 && partes[0].isNotEmpty && partes[1].isNotEmpty) {
      return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
    }
    return limpo.substring(0, limpo.length >= 2 ? 2 : 1).toUpperCase();
  }

  /// Diálogo interativo para alterar a palavra-passe no Auth e na tabela utilizadores
  void _mostrarDialogoAlterarPalavraPasse() {
    final novaSenhaController = TextEditingController();
    final confirmarSenhaController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool aCarregar = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_outlined, color: Colors.blue),
                  SizedBox(width: 10),
                  Text('Alterar Palavra-passe'),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: novaSenhaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Nova Palavra-passe',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.trim().length < 6) {
                          return 'Deve ter pelo menos 6 caracteres.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: confirmarSenhaController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirmar Palavra-passe',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_clock_outlined),
                      ),
                      validator: (v) {
                        if (v != novaSenhaController.text) {
                          return 'As palavras-passe não coincidem.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: aCarregar ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: aCarregar
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          setDialogState(() => aCarregar = true);

                          try {
                            final novaSenha = novaSenhaController.text.trim();

                            // A palavra-passe vive apenas no Supabase Auth, encriptada.
                            // Nunca a guardamos na tabela pública `utilizadores`.
                            await _supabase.auth.updateUser(
                              UserAttributes(password: novaSenha),
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Palavra-passe alterada com sucesso!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => aCarregar = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erro ao alterar palavra-passe: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: aCarregar
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Processa o fecho de turno, descarregando automaticamente o relatório PDF com as métricas do turno
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
      final String? authUserId = widget.utilizadorId ?? _supabase.auth.currentUser?.id; 
      
      int avancosSessao = 0;
      int incidenciasSessao = 0;

      if (authUserId != null) {
        final historicoData = await _supabase
            .from('historico_producao')
            .select('id, data_conclusao, incidencias(id)')
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

      if (!mounted) return;
      Navigator.of(context).pop();

      final String dataHoje = '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';
      
      await PdfService.descarregarRelatorioTurno(
        nomeOperador: _nomeUtilizador,
        dataTurno: dataHoje,
        totalFases: avancosSessao,
        totalIncidencias: incidenciasSessao,
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

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    final List<Widget> telas = [
      const FilaTrabalhoScreen(), // 👈 FIX: Chamada limpa sem parâmetros desconhecidos
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
              children: telas,
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
    final String iniciais = _obterIniciais(_nomeUtilizador);
    final String idDisplay = 'EMP-2026-${_nomeUtilizador.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';

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
                      iniciais,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nomeUtilizador,
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
    final String iniciais = _obterIniciais(_nomeUtilizador);
    final String idDisplay = 'EMP-2026-${_nomeUtilizador.hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';

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
              child: _carregandoPerfil
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.blue.shade600,
                          child: Text(
                            iniciais,
                            style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _nomeUtilizador,
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
                          valor: _emailUtilizador,
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
                          onPressed: _mostrarDialogoAlterarPalavraPasse,
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