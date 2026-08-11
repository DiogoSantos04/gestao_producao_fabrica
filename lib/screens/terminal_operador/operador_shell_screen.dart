import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ecra_recarregavel.dart';
import '../../core/iniciais.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../repositories/operador_repository.dart';
import '../../services/auth_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/dialogo_suporte.dart';
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
  final OperadorRepository _repo = OperadorRepository();
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 0: Minha Fila, 1: Histórico, 2: Relatórios, 3: Perfil.
  int _indiceSelecionado = 0;
  static const int _indicePerfil = 3;

  final DateTime _inicioSessao = DateTime.now();

  String _nomeUtilizador = 'Operador';
  String _emailUtilizador = 'a carregar…';
  bool _carregandoPerfil = true;

  /// `utilizador_id` da sessão — a identidade real do operador.
  String? _utilizadorId;

  StreamSubscription<List<Map<String, dynamic>>>? _subscricaoPerfil;

  /// Chaves dos separadores, para lhes pedir recarregamento ao voltar.
  ///
  /// O `IndexedStack` mantém os quatro separadores vivos: sair e voltar
  /// preserva scroll e filtros, mas antes preservava também os dados, que
  /// podiam ficar obsoletos por tempo indefinido.
  final _chavesEcras = List.generate(3, (_) => GlobalKey<State>());

  static const List<({String titulo, IconData icone})> _menu = [
    (titulo: 'Minha Fila', icone: Icons.assignment_outlined),
    (titulo: 'Histórico', icone: Icons.history_toggle_off),
    (titulo: 'Relatórios', icone: Icons.analytics_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _semearPerfilEmCache();
    _iniciarEscutaPerfil();
  }

  /// Mostra já o perfil que o login carregou, para o cabeçalho não abrir com
  /// "a carregar…" até o stream de `utilizadores` entregar a primeira linha.
  void _semearPerfilEmCache() {
    if (!_authService.temPerfilEmCache) return;

    final identidade = _authService.identidadeParaCabecalho(
      nomeOmissao: 'Operador',
      emailOmissao: 'sem email registado',
    );
    _nomeUtilizador = identidade.nome;
    _emailUtilizador = identidade.email;
    _carregandoPerfil = false;
  }

  @override
  void dispose() {
    _subscricaoPerfil?.cancel();
    super.dispose();
  }

  /// Segue a linha do próprio utilizador em `utilizadores` por WebSocket, para
  /// que uma correção do nome feita pelo admin apareça sem terminar sessão.
  void _iniciarEscutaPerfil() {
    final utilizador = _supabase.auth.currentUser;
    final id = widget.utilizadorId ?? utilizador?.id;

    if (id == null) {
      setState(() => _carregandoPerfil = false);
      return;
    }

    _utilizadorId = id;

    _subscricaoPerfil = _supabase
        .from('utilizadores')
        .stream(primaryKey: ['utilizador_id'])
        .eq('utilizador_id', id)
        .listen(
          (dados) {
            if (!mounted || dados.isEmpty) return;
            final registo = dados.first;
            final nome = registo['nome_utilizador']?.toString().trim();
            final email = registo['email']?.toString().trim();

            setState(() {
              _nomeUtilizador =
                  (nome != null && nome.isNotEmpty) ? nome : 'Operador';
              _emailUtilizador = (email != null && email.isNotEmpty)
                  ? email
                  : (utilizador?.email ?? 'sem email registado');
              _carregandoPerfil = false;
            });
          },
          onError: (erro) {
            if (!mounted) return;
            debugPrint('Aviso Stream Utilizadores (Realtime pode estar desativado): $erro');
            // O perfil é informativo: uma falha aqui é só da atualização em
            // tempo real e não pode apagar um email já correto que a cache do
            // login (ou a própria sessão) já tinha — só cai para a sessão
            // quando ainda não havia nenhum valor carregado.
            setState(() {
              if (_emailUtilizador == 'a carregar…') {
                _emailUtilizador = utilizador?.email ?? 'sem email registado';
              }
              _carregandoPerfil = false;
            });
          },
        );
  }

  /// Iniciais do operador, pela mesma implementação que o painel do admin usa.
  String get _iniciais => obterIniciais(_nomeUtilizador, omissao: 'OP');

  /// Identificador do operador apresentado na interface.
  ///
  /// Deriva do `utilizador_id` da sessão, que é estável. O valor anterior —
  /// `'EMP-2026-' + nome.hashCode` — tinha o ano fixo no código e mudava
  /// sempre que o nome do utilizador fosse corrigido, pelo que não identificava
  /// ninguém de forma fiável.
  String get _idFuncionario {
    final id = _utilizadorId;
    if (id == null || id.isEmpty) return 'ID indisponível';
    return 'OP-${id.replaceAll('-', '').substring(0, 8).toUpperCase()}';
  }

  void _selecionarSeparador(int indice, {required bool fecharDrawer}) {
    final mudou = _indiceSelecionado != indice;
    setState(() => _indiceSelecionado = indice);
    if (fecharDrawer) Navigator.pop(context);

    // Só o separador para onde se entra é recarregado, e só quando é uma
    // mudança real: tocar no separador já ativo não deve disparar uma query.
    if (mudou && indice < _chavesEcras.length) {
      final estado = _chavesEcras[indice].currentState;
      if (estado is EcraRecarregavel) {
        (estado as EcraRecarregavel).recarregar();
      }
    }
  }

  /// Fecha o turno: gera o relatório de atividade e termina a sessão.
  Future<void> _terminarSessao() async {
    // Fechar o turno é irreversível a meio do trabalho e o botão está sempre
    // visível na barra lateral: um toque acidental com luvas terminava a
    // sessão sem aviso.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terminar sessão?'),
        content: const Text(
          'O turno é fechado e o relatório de atividade é gerado. '
          'Terá de voltar a autenticar-se para retomar o trabalho.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar a trabalhar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.erroForte,
              foregroundColor: TemasCores.textoInverso,
            ),
            child: const Text('Terminar sessão'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

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
                      'A compilar o relatório de turno…',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'A processar os avanços e as incidências de hoje.',
                      style: TextStyle(
                        color: TemasCores.textoTerciario,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // O diálogo de progresso é fechado uma única vez, aconteça o que acontecer.
    // Fechá-lo dentro do `try` **e** do `catch` fazia dois `pop` sempre que a
    // geração do PDF falhasse: o segundo desmontava o próprio terminal.
    var falhou = false;
    try {
      final resumo = await _repo.obterResumoDaSessao(_inicioSessao);
      final agora = DateTime.now();
      String d2(int n) => n.toString().padLeft(2, '0');

      await PdfService.descarregarRelatorioTurno(
        nomeOperador: _nomeUtilizador,
        dataTurno: '${d2(agora.day)}/${d2(agora.month)}/${agora.year}',
        totalFases: resumo.fasesConcluidas,
        totalIncidencias: resumo.fasesComParagem,
      );
    } catch (_) {
      falhou = true;
    }

    // O `mounted` não pode travar a saída: o operador já mandou terminar a
    // sessão e sair é a parte que não pode falhar. Só a interface é que precisa
    // do widget vivo.
    if (mounted) {
      Navigator.of(context).pop(); // fecha o diálogo de progresso
      if (falhou) {
        // O relatório é um extra do fecho de turno: falhar a gerá-lo não pode
        // prender o operador numa sessão que ele já mandou terminar. Mas também
        // não pode desaparecer em silêncio, ou o turno fica sem registo.
        context.mostrarMensagem(
          'Sessão terminada, mas não foi possível gerar o relatório de turno.',
          eErro: true,
        );
      }
    }

    await _sair();
  }

  Future<void> _sair() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _alterarPalavraPasse() async {
    final novaController = TextEditingController();
    final confirmarController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool aGuardar = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock_reset_outlined, color: TemasCores.operadorAcento),
              SizedBox(width: 10),
              Flexible(child: Text('Alterar Palavra-passe', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: novaController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Nova Palavra-passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => (v == null || v.trim().length < 6)
                      ? 'Deve ter pelo menos 6 caracteres.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: confirmarController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar Palavra-passe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_clock_outlined),
                  ),
                  validator: (v) => v != novaController.text
                      ? 'As palavras-passe não coincidem.'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: aGuardar ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: aGuardar
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => aGuardar = true);

                      try {
                        // A palavra-passe vive apenas no Supabase Auth,
                        // encriptada. Nunca é escrita na tabela pública
                        // `utilizadores`.
                        await _supabase.auth.updateUser(
                          UserAttributes(password: novaController.text.trim()),
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        context.mostrarMensagem(
                          'Palavra-passe alterada com sucesso.',
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        setDialogState(() => aGuardar = false);
                        context.mostrarMensagem(
                          'Não foi possível alterar a palavra-passe: $e',
                          eErro: true,
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.operadorAcentoForte,
                foregroundColor: TemasCores.textoInverso,
              ),
              child: aGuardar
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: TemasCores.textoInverso,
                      ),
                    )
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    novaController.dispose();
    confirmarController.dispose();
  }

  /// Mostra o email do administrador — sempre acessível a partir da barra
  /// lateral, independentemente de haver uma tarefa aberta. O diálogo é
  /// partilhado com o resto da app ([mostrarDialogoSuporte]).
  void _contactarAdministrador() {
    mostrarDialogoSuporte(
      context,
      aoObterEmail: _repo.obterEmailSuporte,
      titulo: 'Contactar Administrador',
      descricao: 'Contacte o administrador para dúvidas, incidências ou pedidos de apoio.',
      rotuloEmail: 'Email do Administrador',
      corAcento: TemasCores.operadorAcento,
      assunto: 'Terminal Operador - Suporte ($_idFuncionario)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final eDesktop = MediaQuery.of(context).size.width > 950;

    final telas = <Widget>[
      FilaTrabalhoScreen(key: _chavesEcras[0]),
      HistoricoOperadorScreen(key: _chavesEcras[1]),
      RelatoriosOperadorScreen(key: _chavesEcras[2]),
      _construirEcraPerfil(),
    ];

    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
      appBar: eDesktop
          ? null
          : AppBar(
              backgroundColor: TemasCores.superficie,
              foregroundColor: TemasCores.textoPrimario,
              elevation: 0,
              scrolledUnderElevation: 1,
              surfaceTintColor: TemasCores.superficie,
              title: Row(
                children: [
                  const Icon(
                    Icons.precision_manufacturing,
                    color: TemasCores.operadorAcento,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _indiceSelecionado == _indicePerfil
                          ? 'O Meu Perfil'
                          : _menu[_indiceSelecionado].titulo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
      drawer:
          eDesktop ? null : Drawer(child: _construirBarra(dentroDrawer: true)),
      body: Row(
        children: [
          if (eDesktop)
            SizedBox(width: 260, child: _construirBarra(dentroDrawer: false)),
          Expanded(
            child: IndexedStack(index: _indiceSelecionado, children: telas),
          ),
        ],
      ),
    );
  }

  Widget _construirBarra({required bool dentroDrawer}) {
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
                      colors: [TemasCores.operadorAcentoClaro, TemasCores.operadorAcentoForte],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.precision_manufacturing,
                    color: TemasCores.textoInverso,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TERMINAL',
                        style: TextStyle(
                          color: TemasCores.textoInversoTenue,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      Text(
                        'Operador',
                        style: TextStyle(
                          color: TemasCores.textoInverso,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
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
              itemCount: _menu.length,
              itemBuilder: (context, index) {
                final item = _menu[index];
                final selecionado = _indiceSelecionado == index;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _selecionarSeparador(
                        index,
                        fecharDrawer: dentroDrawer,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: selecionado
                              ? TemasCores.operadorAcento.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: selecionado
                                  ? TemasCores.operadorAcentoClaro
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            Icon(
                              item.icone,
                              color: selecionado
                                  ? TemasCores.operadorAcentoClaro
                                  : TemasCores.textoInversoTenue,
                              size: 20,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                item.titulo,
                                style: TextStyle(
                                  color: selecionado
                                      ? TemasCores.textoInverso
                                      : TemasCores.textoInversoClaro,
                                  fontSize: 14,
                                  fontWeight: selecionado
                                      ? FontWeight.w600
                                      : FontWeight.normal,
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
          const Divider(color: TemasCores.separadorEscuro, height: 1),
          _construirRodape(dentroDrawer),
        ],
      ),
    );
  }

  Widget _construirRodape(bool dentroDrawer) {
    final noPerfil = _indiceSelecionado == _indicePerfil;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selecionarSeparador(
                _indicePerfil,
                fecharDrawer: dentroDrawer,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10.0),
                decoration: BoxDecoration(
                  color: noPerfil
                      ? TemasCores.operadorAcento.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: TemasCores.operadorAcentoClaro,
                      radius: 18,
                      child: Text(
                        _iniciais,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.textoInverso,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nomeUtilizador,
                            style: const TextStyle(
                              color: TemasCores.textoInverso,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _idFuncionario,
                            style: const TextStyle(
                              color: TemasCores.textoInversoTenue,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: TemasCores.textoInversoTenue,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _contactarAdministrador,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: TemasCores.operadorAcento.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mail_outline_rounded,
                      size: 15,
                      color: TemasCores.operadorAcentoClaro,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Contactar Administrador',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TemasCores.operadorAcentoClaro,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _terminarSessao,
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
                    Icon(
                      Icons.logout_rounded,
                      size: 15,
                      color: TemasCores.erroClaro,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Terminar Sessão',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: TemasCores.erroClaro,
                      ),
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

  Widget _construirEcraPerfil() {
    final String iniciais = _iniciais;
    final String idDisplay = _idFuncionario;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            shadowColor: TemasCores.operadorAcento.withValues(alpha: 0.25),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
                                colors: [
                                  TemasCores.operadorAcentoClaro,
                                  TemasCores.operadorAcentoForte,
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 46,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: TemasCores.superficie,
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 42,
                                backgroundColor: TemasCores.operadorAcento,
                                child: Text(
                                  iniciais,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    color: TemasCores.textoInverso,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: TemasCores.textoPrimario,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: TemasCores.operadorAcentoFundo,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Operador de Produção',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: TemasCores.operadorAcentoForte,
                                ),
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
                              label: 'ID do Funcionário',
                              valor: idDisplay,
                              icone: Icons.badge_outlined,
                            ),
                            const SizedBox(height: 28),

                            OutlinedButton.icon(
                              onPressed: _alterarPalavraPasse,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: TemasCores.textoPrimario,
                                side: const BorderSide(
                                  color: TemasCores.bordaForte,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.vpn_key_outlined,
                                size: 18,
                              ),
                              label: const Text('Alterar Palavra-passe'),
                            ),
                            const SizedBox(height: 10),

                            OutlinedButton.icon(
                              onPressed: _terminarSessao,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: TemasCores.erroForte,
                                side: const BorderSide(
                                  color: TemasCores.erroBorda,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
              color: TemasCores.operadorAcentoFundo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: TemasCores.operadorAcentoForte, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: TemasCores.textoTerciario,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: TemasCores.textoPrimario,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
