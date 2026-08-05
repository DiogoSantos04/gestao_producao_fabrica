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
            // O perfil é informativo: uma falha aqui não pode tapar o terminal.
            setState(() {
              _emailUtilizador = 'Não foi possível carregar o email';
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
              Icon(Icons.lock_reset_outlined, color: TemasCores.info),
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
                backgroundColor: TemasCores.infoForte,
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
      appBar: eDesktop
          ? null
          : AppBar(
              title: Text(
                _indiceSelecionado == _indicePerfil
                    ? 'O Meu Perfil'
                    : _menu[_indiceSelecionado].titulo,
              ),
              backgroundColor: TemasCores.superficie,
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
    return Container(
      color: TemasCores.marcaEscura,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: const Row(
              children: [
                Icon(
                  Icons.precision_manufacturing,
                  color: TemasCores.marcaAcento,
                  size: 28,
                ),
                SizedBox(width: 12),
                Text(
                  'Terminal Operador',
                  style: TextStyle(
                    color: TemasCores.textoInverso,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: TemasCores.separadorEscuro, height: 1),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _menu.length,
              itemBuilder: (context, index) {
                final item = _menu[index];
                final selecionado = _indiceSelecionado == index;

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  child: ListTile(
                    selected: selecionado,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    selectedTileColor: TemasCores.realceSobreEscuro,
                    leading: Icon(
                      item.icone,
                      color: selecionado
                          ? TemasCores.marcaAcento
                          : TemasCores.textoInversoTenue,
                      size: 20,
                    ),
                    title: Text(
                      item.titulo,
                      style: TextStyle(
                        color: selecionado
                            ? TemasCores.textoInverso
                            : TemasCores.textoInversoSuave,
                        fontSize: 14,
                        fontWeight:
                            selecionado ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    onTap: () => _selecionarSeparador(
                      index,
                      fecharDrawer: dentroDrawer,
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
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InkWell(
            onTap: () => _selecionarSeparador(
              _indicePerfil,
              fecharDrawer: dentroDrawer,
            ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: noPerfil
                    ? TemasCores.realceSobreEscuro
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: TemasCores.infoFundoForte,
                    radius: 18,
                    child: Text(
                      _iniciais,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TemasCores.infoForte,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _terminarSessao,
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.erro.withValues(alpha: 0.15),
              foregroundColor: TemasCores.erroVivo,
              elevation: 0,
              minimumSize: const Size.fromHeight(38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: const Text(
              'Terminar Sessão',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirEcraPerfil() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: _carregandoPerfil
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: TemasCores.infoForte,
                          child: Text(
                            _iniciais,
                            style: const TextStyle(
                              fontSize: 28,
                              color: TemasCores.textoInverso,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _nomeUtilizador,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Operador Industrial',
                          style: TextStyle(
                            fontSize: 14,
                            color: TemasCores.textoTerciario,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Divider(height: 40),
                        _CampoInformativo(
                          rotulo: 'Email Institucional',
                          valor: _emailUtilizador,
                          icone: Icons.email_outlined,
                        ),
                        const SizedBox(height: 16),
                        _CampoInformativo(
                          rotulo: 'ID do Funcionário',
                          valor: _idFuncionario,
                          icone: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 32),
                        OutlinedButton.icon(
                          onPressed: _alterarPalavraPasse,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            side: const BorderSide(
                              color: TemasCores.bordaForte,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(
                            Icons.vpn_key_outlined,
                            color: TemasCores.textoPrimario,
                          ),
                          label: const Text(
                            'Alterar Palavra-passe',
                            style: TextStyle(color: TemasCores.textoPrimario),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _terminarSessao,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TemasCores.erroForte,
                            foregroundColor: TemasCores.textoInverso,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
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
}

/// Campo só de leitura do cartão de perfil.
class _CampoInformativo extends StatelessWidget {
  const _CampoInformativo({
    required this.rotulo,
    required this.valor,
    required this.icone,
  });

  final String rotulo;
  final String valor;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        children: [
          Icon(icone, color: TemasCores.textoTerciario),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: const TextStyle(
                    fontSize: 11,
                    color: TemasCores.textoTerciario,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
