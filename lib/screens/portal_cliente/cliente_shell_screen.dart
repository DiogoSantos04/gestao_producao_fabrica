import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/iniciais.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../services/auth_service.dart';
import '../../widgets/dialogo_suporte.dart';
import '../login_screen.dart';
import 'rastreio_cliente_screen.dart';
import 'historico_cliente_screen.dart';
import 'solicitar_encomenda_screen.dart';

class ClienteShellScreen extends StatefulWidget {
  const ClienteShellScreen({super.key});

  @override
  State<ClienteShellScreen> createState() => _ClienteShellScreenState();
}

class _ClienteShellScreenState extends State<ClienteShellScreen> {
  final AuthService _authService = AuthService();
  final PortalClienteRepository _repositorio = PortalClienteRepository();
  final _supabase = Supabase.instance.client;

  /// Notificações já mostradas nesta sessão.
  ///
  /// O `stream()` do Supabase reemite a **lista completa** a cada alteração, e
  /// não apenas a linha nova. Sem este registo, uma notificação nova fazia
  /// reaparecer o SnackBar de todas as anteriores que ainda estivessem por ler.
  final Set<Object> _notificacoesApresentadas = {};

  // Chave global para comunicar com o ecrã de Solicitar Encomenda
  final GlobalKey<SolicitarEncomendaScreenState> _solicitarKey = GlobalKey();

  int _indiceAtual = 0; // 0: Início, 1: Histórico, 2: Novo Pedido, 3: Perfil

  String _nomeUtilizador = 'Cliente';
  String _emailUtilizador = 'carregando...';
  bool _carregandoPerfil = true;

  StreamSubscription<Map<String, dynamic>?>? _utilizadorStreamSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _notificacoesStreamSubscription;

  final List<Map<String, dynamic>> _menuItens = [
    {'titulo': 'Início / Rastreio', 'icone': Icons.search_outlined},
    {'titulo': 'O Meu Histórico', 'icone': Icons.receipt_long_outlined},
    {'titulo': 'Novo Pedido', 'icone': Icons.add_shopping_cart_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _semearPerfilEmCache();
    _iniciarEscutaPerfilEmTempoReal();
    _iniciarEscutaNotificacoesEmTempoReal();
  }

  @override
  void dispose() {
    _utilizadorStreamSubscription?.cancel();
    _notificacoesStreamSubscription?.cancel();
    super.dispose();
  }

  /// Mostra já o perfil que o login carregou, para o cabeçalho não abrir com
  /// "carregando..." até o stream de `utilizadores` entregar a primeira linha.
  void _semearPerfilEmCache() {
    if (!_authService.temPerfilEmCache) return;

    final identidade = _authService.identidadeParaCabecalho(
      nomeOmissao: 'Cliente',
      emailOmissao: 'cliente@factory.com',
    );
    _nomeUtilizador = identidade.nome;
    _emailUtilizador = identidade.email;
    _carregandoPerfil = false;
  }

  void _iniciarEscutaPerfilEmTempoReal() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _utilizadorStreamSubscription = _repositorio.escutarPerfil().listen(
      (registo) {
        if (!mounted || registo == null) return;

        final String? nomeDb = registo['nome_utilizador']?.toString();
        final String? emailDb = registo['email']?.toString();

        setState(() {
          _nomeUtilizador = (nomeDb != null && nomeDb.trim().isNotEmpty) ? nomeDb : 'Cliente';
          _emailUtilizador = (emailDb != null && emailDb.trim().isNotEmpty)
              ? emailDb
              : (user.email ?? 'cliente@factory.com');
          _carregandoPerfil = false;
        });
      },
      onError: (erro) {
        debugPrint('Aviso Stream Utilizadores: $erro');
        if (mounted) setState(() => _carregandoPerfil = false);
      },
    );
  }

  void _iniciarEscutaNotificacoesEmTempoReal() {
    _notificacoesStreamSubscription = _repositorio.escutarNotificacoes().listen(
      (notificacoes) {
        if (!mounted) return;

        for (final n in notificacoes) {
          final Object? id = n['id'] as Object?;
          if (id == null || n['lida'] == true) continue;

          // Uma notificação só é mostrada uma vez por sessão, mesmo que a
          // marcação de lida no servidor falhe: o contrário dava um ciclo de
          // SnackBars a cada nova emissão do stream.
          if (!_notificacoesApresentadas.add(id)) continue;

          _exibirNotificacaoAoVivo(
            id,
            n['titulo']?.toString() ?? '',
            n['mensagem']?.toString() ?? '',
          );
        }
      },
      onError: (erro) {
        debugPrint('Aviso Stream Notificações (Realtime pode estar desativado): $erro');
      },
    );
  }

  void _exibirNotificacaoAoVivo(Object notificacaoId, String titulo, String mensagem) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: TemasCores.clienteAcentoForte,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: TemasCores.avisoBorda, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(mensagem, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // A marcação era disparada sem `await` nem tratamento de erro: falhando,
      // a notificação voltava na emissão seguinte do stream.
      try {
        await _repositorio.marcarNotificacaoLida(notificacaoId);
      } on RepositoryException catch (e) {
        debugPrint('Não foi possível marcar a notificação como lida: ${e.mensagem}');
      }
    });
  }

  /// Iniciais do cliente, pela mesma implementação que os outros dois perfis.
  String get _iniciais => obterIniciais(_nomeUtilizador, omissao: 'CL');

  /// Identificador do cliente apresentado na interface.
  ///
  /// Mantém o formato anterior, mas deixa de estar escrito em dois sítios.
  String get _idCliente {
    final digitos = _nomeUtilizador.hashCode.abs().toString().padLeft(4, '0');
    return 'CLI-2026-${digitos.substring(0, 4)}';
  }

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
                  Icon(Icons.lock_reset_outlined, color: TemasCores.clienteAcento),
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
                        if (v == null || v.trim().length < 6) return 'Deve ter pelo menos 6 caracteres.';
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
                        if (v != novaSenhaController.text) return 'As palavras-passe não coincidem.';
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
                    backgroundColor: TemasCores.clienteAcento,
                    foregroundColor: TemasCores.textoInverso,
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

  Widget _construirEcraPerfil() {
    final String iniciais = _iniciais;
    final String idDisplay = _idCliente;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            shadowColor: TemasCores.clienteAcento.withValues(alpha: 0.25),
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
                                colors: [TemasCores.clienteAcentoClaro, TemasCores.clienteAcentoForte],
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
                                backgroundColor: TemasCores.clienteAcento,
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
                                color: TemasCores.clienteAcentoFundo,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Cliente Comercial',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.clienteAcentoForte),
                              ),
                            ),
                            const SizedBox(height: 28),

                            _construirCampoInformativo(
                              label: 'Email Registado',
                              valor: _emailUtilizador,
                              icone: Icons.email_outlined,
                            ),
                            const SizedBox(height: 12),
                            _construirCampoInformativo(
                              label: 'Código do Cliente',
                              valor: idDisplay,
                              icone: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 28),

                            OutlinedButton.icon(
                              onPressed: () => mostrarDialogoSuporte(context, aoObterEmail: _repositorio.obterEmailSuporte),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: TemasCores.clienteAcentoForte,
                                side: const BorderSide(color: TemasCores.clienteAcentoClaro),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.support_agent_outlined, size: 18),
                              label: const Text('Contactar Suporte'),
                            ),
                            const SizedBox(height: 10),

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
              color: TemasCores.clienteAcentoFundo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: TemasCores.clienteAcentoForte, size: 18),
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

    final List<Widget> telas = [
      const RastreioClienteScreen(),
      HistoricoClienteScreen(
        onRepetirEncomenda: (tipoProdutoId, quantidade) {
          // Preenche os dados no formulário através da chave global
          _solicitarKey.currentState?.preencherParaRepeticao(
            tipoProdutoId: tipoProdutoId,
            quantidade: quantidade,
          );

          setState(() {
            _indiceAtual = 2; // Redireciona para o separador Novo Pedido
          });

          context.mostrarSnack(
            'Pedido preenchido com sucesso! Reveja os dados e submeta.',
            cor: TemasCores.clienteAcento,
          );
        },
      ),
      SolicitarEncomendaScreen(key: _solicitarKey),
      _construirEcraPerfil(),
    ];

    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
      appBar: !eDesktop
          ? AppBar(
              backgroundColor: TemasCores.superficie,
              foregroundColor: TemasCores.textoPrimario,
              elevation: 0,
              scrolledUnderElevation: 1,
              surfaceTintColor: TemasCores.superficie,
              title: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, color: TemasCores.clienteAcento, size: 20),
                  const SizedBox(width: 10),
                  Text(_indiceAtual == 3 ? 'O Meu Perfil' : _menuItens[_indiceAtual]['titulo']),
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
                      colors: [TemasCores.clienteAcentoClaro, TemasCores.clienteAcentoForte],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_shipping_outlined, color: TemasCores.textoInverso, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PORTAL',
                        style: TextStyle(
                          color: TemasCores.textoInversoTenue,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'Cliente',
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
                        setState(() => _indiceAtual = index);
                        if (dentroDrawer) Navigator.pop(context);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        decoration: BoxDecoration(
                          color: estaSelecionado
                              ? TemasCores.clienteAcento.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: estaSelecionado ? TemasCores.clienteAcentoClaro : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Icon(
                              item['icone'],
                              color: estaSelecionado ? TemasCores.clienteAcentoClaro : TemasCores.textoInversoTenue,
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

          // O suporte é uma ação, não um separador: fica fora da lista para não
          // desalinhar os índices do `IndexedStack`, mas continua acessível de
          // qualquer ecrã do portal.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (dentroDrawer) Navigator.pop(context);
                  mostrarDialogoSuporte(context, aoObterEmail: _repositorio.obterEmailSuporte);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: const Row(
                    children: [
                      SizedBox(width: 4),
                      Icon(Icons.support_agent_outlined, color: TemasCores.textoInversoTenue, size: 20),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Ajuda e Suporte',
                          style: TextStyle(color: TemasCores.textoInversoClaro, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Divider(color: TemasCores.separadorEscuro, height: 1),
          _buildRodapeSidebar(dentroDrawer),
        ],
      ),
    );
  }

  Widget _buildRodapeSidebar(bool dentroDrawer) {
    final bool estaNoPerfil = _indiceAtual == 3;
    final String iniciais = _iniciais;
    final String idDisplay = _idCliente;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() => _indiceAtual = 3);
                if (dentroDrawer) Navigator.pop(context);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: estaNoPerfil ? TemasCores.clienteAcento.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: TemasCores.clienteAcentoClaro,
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