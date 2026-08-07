import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/iniciais.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/estado_ordem.dart';
import '../../models/utilizador_model.dart';
import '../../repositories/utilizadores_repository.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';

// Importa os ecrãs desenvolvidos
import 'dashboard_principal_screen.dart';
import 'gestao_utilizadores_screen.dart';
import 'criar_encomenda_screen.dart'; 
import 'painel_controlo_screen.dart'; 
import 'gestao_fluxos_screen.dart';
import 'informacoes_clientes_screen.dart'; 
import 'relatorios_admin_screen.dart';
import 'pedidos_clientes_admin_screen.dart';
import 'postos_trabalho_screen.dart'; // 👈 IMPORTADO: Novo ecrã de Gestão de Postos

class DashboardAdminShell extends StatefulWidget {
  const DashboardAdminShell({super.key});

  @override
  State<DashboardAdminShell> createState() => _DashboardAdminShellState();
}

class _DashboardAdminShellState extends State<DashboardAdminShell> {
  final AuthService _authService = AuthService();
  final _utilizadoresRepo = UtilizadoresRepository();

  int _indiceAtual = 0; // 0 a 8: Menus Principais, 9: O Meu Perfil

  /// Índice de "Ordens em Curso" na barra lateral.
  static const int _indiceOrdens = 5;

  /// Filtro com que "Ordens em Curso" abre. Muda quando um KPI do dashboard
  /// pede para ver as ordens por trás do número.
  FiltroEstadoOrdem _filtroOrdens = FiltroEstadoOrdem.todos;

  /// Leva o utilizador ao painel de controlo já filtrado.
  ///
  /// A `ValueKey` é deliberada: obriga o painel a ser reconstruído de raiz
  /// quando o filtro muda. Sem ela, o `IndexedStack` reaproveitaria o `State`
  /// que já existe, o `initState` não voltaria a correr e o ecrã abria com a
  /// lista e a paginação do filtro anterior.
  void _abrirOrdens(FiltroEstadoOrdem filtro) {
    setState(() {
      _filtroOrdens = filtro;
      _indiceAtual = _indiceOrdens;
    });
  }

  // Dados dinâmicos do administrador autenticado
  String _nomeUtilizador = 'Administrador';
  String _emailUtilizador = 'carregando...';
  bool _carregandoPerfil = true;

  // Subscrição em tempo real da base de dados
  StreamSubscription<List<Map<String, dynamic>>>? _utilizadorStreamSubscription;

  // Lista dos menus correspondentes às opções da barra lateral
  final List<Map<String, dynamic>> _menuItens = [
    {'titulo': 'Dashboard', 'icone': Icons.dashboard_outlined},
    {'titulo': 'Fluxos Produtivos', 'icone': Icons.schema_outlined},
    {'titulo': 'Utilizadores', 'icone': Icons.people_alt_outlined},
    {'titulo': 'Pedidos Clientes', 'icone': Icons.pending_actions_outlined},
    {'titulo': 'Planeamento', 'icone': Icons.assignment_outlined},
    {'titulo': 'Ordens em Curso', 'icone': Icons.precision_manufacturing_outlined},
    {'titulo': 'Postos de Trabalho', 'icone': Icons.factory_outlined}, // 👈 NOVO MENU (Índice 6)
    {'titulo': 'Clientes', 'icone': Icons.business_center_outlined},
    {'titulo': 'Relatórios', 'icone': Icons.analytics_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _semearPerfilEmCache();
    _confirmarSessaoDeAdministrador();
    _iniciarEscutaEmTempoReal();
  }

  /// Verifica que a sessão do Auth pertence mesmo a um administrador.
  ///
  /// A cache de perfil do [AuthService] é de um singleton e sobrevive a trocas
  /// de sessão: bastava a sessão passar a ser de outra conta para este ecrã
  /// continuar a mostrar o nome do administrador anterior enquanto as escritas
  /// já iam assinadas pelo novo utilizador. O resultado era um erro sem nexo
  /// aparente — "Apenas o Administrador pode alterar o perfil de acesso." vindo
  /// do trigger `impedir_autopromocao`, num ecrã que se dizia de administrador.
  ///
  /// A base de dados nunca chegou a estar em risco (o trigger recusou); o que
  /// faltava era a aplicação admitir que a sessão não era a que aparentava.
  Future<void> _confirmarSessaoDeAdministrador() async {
    final String? uid = _utilizadoresRepo.utilizadorAtualId;

    // Sem sessão não há nada a validar: o arranque da app já encaminha para o
    // login nesse caso.
    if (uid == null) return;

    final PerfilUtilizador perfil;
    try {
      perfil = (await _authService.obterUtilizadorPorId(uid)).perfil;
    } catch (_) {
      // Uma falha de rede não pode expulsar quem está a trabalhar: as escritas
      // continuam protegidas pelas políticas e triggers do lado do servidor.
      return;
    }

    if (!mounted || perfil == PerfilUtilizador.administrador) return;

    await _authService.logout();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    context.mostrarMensagem(
      'A sessão ativa não é de administrador. Inicie sessão novamente.',
      eErro: true,
    );
  }

  /// Mostra já o perfil que o login carregou, para o cabeçalho não abrir com
  /// "carregando..." até o stream de `utilizadores` entregar a primeira linha.
  void _semearPerfilEmCache() {
    if (!_authService.temPerfilEmCache) return;

    final identidade = _authService.identidadeParaCabecalho(
      nomeOmissao: 'Administrador',
      emailOmissao: 'admin@factory.com',
    );
    _nomeUtilizador = identidade.nome;
    _emailUtilizador = identidade.email;
    _carregandoPerfil = false;
  }

  @override
  void dispose() {
    // Cancela o canal de WebSocket ao fechar o ecrã para libertar memória
    _utilizadorStreamSubscription?.cancel();
    super.dispose();
  }

  /// Subscreve a tabela 'utilizadores' via WebSocket para atualizações em tempo real
  void _iniciarEscutaEmTempoReal() {
    try {
      final stream = _utilizadoresRepo.escutarPerfilAtual();
      if (stream == null) return;
      final emailSessao = _utilizadoresRepo.utilizadorAtualEmail;

      _utilizadorStreamSubscription = stream.listen(
            (dados) {
              if (mounted && dados.isNotEmpty) {
                final registo = dados.first;
                final String? nomeDb = registo['nome_utilizador']?.toString();
                final String? emailDb = registo['email']?.toString();

                setState(() {
                  _nomeUtilizador = (nomeDb != null && nomeDb.trim().isNotEmpty)
                      ? nomeDb
                      : 'Administrador';
                  _emailUtilizador = (emailDb != null && emailDb.trim().isNotEmpty)
                      ? emailDb
                      : (emailSessao ?? 'admin@factory.com');
                  _carregandoPerfil = false;
                });
              }
            },
            onError: (erro) {
              debugPrint('Erro na escuta em tempo real: $erro');
              if (mounted) setState(() => _carregandoPerfil = false);
            },
          );
    } catch (e) {
      debugPrint('Erro ao iniciar stream do perfil: $e');
      if (mounted) setState(() => _carregandoPerfil = false);
    }
  }

  String _obterIniciais(String? nome) => obterIniciais(nome, omissao: 'AD');

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
                  Icon(Icons.lock_reset_outlined, color: TemasCores.adminAcento),
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
                            await _utilizadoresRepo.alterarPalavraPasse(novaSenha);

                            if (context.mounted) {
                              Navigator.pop(context);
                              context.mostrarMensagem('Palavra-passe alterada com sucesso!');
                            }
                          } catch (e) {
                            setDialogState(() => aCarregar = false);
                            if (context.mounted) {
                              context.mostrarMensagem('Erro ao alterar palavra-passe: $e', eErro: true);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemasCores.adminAcento,
                    foregroundColor: TemasCores.textoInverso,
                  ),
                  child: aCarregar
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
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

  /// Constrói o ecrã completo de Perfil do Administrador
  /// Identificador estável do administrador, derivado do UUID real da conta.
  /// Antes vinha do `hashCode` do nome, pelo que mudava sempre que o nome mudava
  /// e o ano estava fixo em 2026.
  String get _idAdministrador {
    final uid = _utilizadoresRepo.utilizadorAtualId;
    if (uid == null) return 'ADM-------';
    return 'ADM-${uid.substring(0, 8).toUpperCase()}';
  }

  Widget _construirEcraPerfil() {
    final String iniciais = _obterIniciais(_nomeUtilizador);
    final String idDisplay = _idAdministrador;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            shadowColor: TemasCores.adminAcento.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: _carregandoPerfil
                ? const Padding(
                    padding: EdgeInsets.all(64.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          Container(
                            height: 88,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [TemasCores.adminAcentoClaro, TemasCores.adminAcentoForte],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 46,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: TemasCores.superficie, shape: BoxShape.circle),
                              child: CircleAvatar(
                                radius: 42,
                                backgroundColor: TemasCores.adminAcento,
                                child: Text(
                                  iniciais,
                                  style: const TextStyle(fontSize: 26, color: TemasCores.textoInverso, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 56, 32, 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _nomeUtilizador,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: TemasCores.adminAcentoFundo,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Administrador do Sistema',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.adminAcentoForte),
                              ),
                            ),
                            const SizedBox(height: 28),

                            _construirCampoInformativo(
                              label: 'Email Institucional',
                              valor: _emailUtilizador,
                              icone: Icons.email_outlined,
                            ),
                            const SizedBox(height: 12),
                            _construirCampoInformativo(
                              label: 'ID do Administrador',
                              valor: idDisplay,
                              icone: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 28),

                            OutlinedButton.icon(
                              onPressed: _mostrarDialogoAlterarPalavraPasse,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: TemasCores.textoPrimario,
                                side: const BorderSide(color: TemasCores.bordaForte),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.vpn_key_outlined, size: 18),
                              label: const Text('Alterar Palavra-passe'),
                            ),
                            const SizedBox(height: 10),

                            OutlinedButton.icon(
                              onPressed: _efetuarLogout,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: TemasCores.erroForte,
                                side: const BorderSide(color: TemasCores.erroBorda),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text('Terminar Sessão'),
                            ),
                          ],
                        ),
                      ),
                    ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(width: 1, color: TemasCores.borda),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TemasCores.adminAcentoFundo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: TemasCores.adminAcentoForte, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: TemasCores.textoTerciario, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TemasCores.textoPrimario),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    // Lista de ecrãs renderizados à direita (Postos de Trabalho no índice 6 e Perfil no índice 9)
    final List<Widget> telas = [
      DashboardPrincipalScreen(aoAbrirOrdens: _abrirOrdens),
      const GestaoFluxosScreen(),
      const GestaoUtilizadoresScreen(),
      const PedidosClientesAdminScreen(),
      const CriarEncomendaScreen(),
      PainelControloScreen(
        key: ValueKey(_filtroOrdens),
        filtroInicial: _filtroOrdens,
      ),
      const PostosTrabalhoScreen(),        // 👈 Index 6: Postos de Trabalho
      const ClientesScreen(),
      const RelatoriosAdminScreen(),
      _construirEcraPerfil(),             // 👈 Index 9: Perfil do Administrador
    ];

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      appBar: !eDesktop
          ? AppBar(
              backgroundColor: TemasCores.superficie,
              foregroundColor: TemasCores.textoPrimario,
              elevation: 0,
              scrolledUnderElevation: 1,
              surfaceTintColor: TemasCores.superficie,
              title: Row(
                children: [
                  const Icon(Icons.settings_suggest_rounded, color: TemasCores.adminAcento, size: 20),
                  const SizedBox(width: 10),
                  Text(_indiceAtual == 9 ? 'O Meu Perfil' : _menuItens[_indiceAtual]['titulo']),
                ],
              ),
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
              index: _indiceAtual,
              children: telas,
            ),
          ),
        ],
      ),
    );
  }

  // --- CONSTRUTOR DA SIDEBAR ---
  Widget _buildSidebar({required bool dentroDrawer}) {
    return Material(
      color: TemasCores.marcaEscura,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [TemasCores.adminAcentoClaro, TemasCores.adminAcentoForte],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.settings_suggest_rounded, color: TemasCores.textoInverso, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SISTEMA',
                        style: TextStyle(
                          color: TemasCores.textoInversoTenue,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'Industrial',
                        style: TextStyle(color: TemasCores.textoInverso, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: TemasCores.separadorEscuro, height: 1),
          const SizedBox(height: 12),

          // Lista de Opções do Menu
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _menuItens.length,
              itemBuilder: (context, index) {
                final item = _menuItens[index];
                final bool estaSelecionado = _indiceAtual == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _indiceAtual = index;
                          // Entrar pelo menu é um pedido para ver as ordens
                          // todas: o filtro que veio de um KPI não pode ficar
                          // agarrado ao ecrã sem que ninguém o tenha pedido.
                          if (index == _indiceOrdens) {
                            _filtroOrdens = FiltroEstadoOrdem.todos;
                          }
                        });
                        if (dentroDrawer) {
                          Navigator.pop(context);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: estaSelecionado
                              ? TemasCores.adminAcento.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: estaSelecionado ? TemasCores.adminAcentoClaro : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Icon(
                              item['icone'],
                              color: estaSelecionado ? TemasCores.adminAcentoClaro : TemasCores.textoInversoTenue,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item['titulo'],
                                style: TextStyle(
                                  color: estaSelecionado ? TemasCores.textoInverso : TemasCores.textoInversoClaro,
                                  fontSize: 14,
                                  fontWeight: estaSelecionado ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Rodapé com o Logout e Info do Utilizador
          const Divider(color: TemasCores.separadorEscuro, height: 1),
          _buildRodapeSidebar(dentroDrawer),
        ],
      ),
    );
  }

  // --- SECÇÃO DE LOGOUT / PERFIL ---
  Widget _buildRodapeSidebar(bool dentroDrawer) {
    final bool estaNoPerfil = _indiceAtual == 9;
    final String iniciais = _obterIniciais(_nomeUtilizador);
    final String idDisplay = _idAdministrador;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _indiceAtual = 9;
                });
                if (dentroDrawer) {
                  Navigator.pop(context);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: estaNoPerfil ? TemasCores.adminAcento.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: TemasCores.adminAcentoClaro,
                      radius: 18,
                      child: Text(
                        iniciais,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: TemasCores.textoInverso),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nomeUtilizador,
                            style: const TextStyle(color: TemasCores.textoInverso, fontSize: 13, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            idDisplay,
                            style: const TextStyle(color: TemasCores.textoInversoTenue, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: TemasCores.textoInversoTenue, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _efetuarLogout,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: TemasCores.erro.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 15, color: TemasCores.erroClaro),
                    SizedBox(width: 8),
                    Text(
                      'Terminar Sessão',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.erroClaro),
                    ),
                  ],
                ),
              ),
            ),
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