import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/breakpoints.dart';
import '../../core/ecra_recarregavel.dart';
import '../../core/iniciais.dart';
import '../../core/temas_cores.dart';
import '../../repositories/tecnico_repository.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';
import 'fila_manutencao_screen.dart';
import 'historico_tecnico_screen.dart';

/// Terminal do técnico de manutenção.
///
/// Dois separadores: as avarias por resolver e o que este técnico já fechou. O
/// `IndexedStack` mantém ambos vivos — voltar à fila preserva o scroll — mas por
/// isso mesmo o separador para onde se entra é recarregado, ou ficaria a mostrar
/// o estado da linha de há uma hora.
class TecnicoShellScreen extends StatefulWidget {
  const TecnicoShellScreen({super.key});

  @override
  State<TecnicoShellScreen> createState() => _TecnicoShellScreenState();
}

class _TecnicoShellScreenState extends State<TecnicoShellScreen> {
  final AuthService _authService = AuthService();
  final TecnicoRepository _repo = TecnicoRepository();

  int _indice = 0;

  final _chaves = List.generate(2, (_) => GlobalKey<State>());

  StreamSubscription<List<Map<String, dynamic>>>? _subscricaoNotificacoes;

  /// Notificações já mostradas nesta sessão.
  ///
  /// O stream reemite a lista inteira a cada alteração; sem esta memória, cada
  /// nova avaria fazia reaparecer os avisos de todas as anteriores.
  final Set<Object> _jaApresentadas = {};

  @override
  void initState() {
    super.initState();
    _escutarNotificacoes();
  }

  @override
  void dispose() {
    _subscricaoNotificacoes?.cancel();
    super.dispose();
  }

  void _escutarNotificacoes() {
    _subscricaoNotificacoes = _repo.escutarNotificacoes().listen(
      (notificacoes) {
        if (!mounted) return;

        for (final n in notificacoes) {
          final Object? id = n['id'] as Object?;
          if (id == null || n['lida'] == true) continue;
          if (!_jaApresentadas.add(id)) continue;

          _avisar(
            id,
            n['titulo']?.toString() ?? 'Nova avaria',
            n['mensagem']?.toString() ?? '',
          );
        }
      },
      onError: (erro) {
        // O aviso ao vivo é um extra: a fila continua a ser a fonte de verdade e
        // o técnico chega lá pelo separador, mesmo com o Realtime desligado.
        debugPrint('Aviso Stream Notificações (Realtime pode estar desativado): $erro');
      },
    );
  }

  void _avisar(Object notificacaoId, String titulo, String mensagem) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          backgroundColor: TemasCores.avisoTextoForte,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: TemasCores.avisoBorda,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: TemasCores.textoInverso,
                      ),
                    ),
                    if (mensagem.isNotEmpty)
                      Text(
                        mensagem,
                        style: const TextStyle(
                          fontSize: 12,
                          color: TemasCores.textoInverso,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'VER FILA',
            textColor: TemasCores.textoInverso,
            onPressed: () => _selecionar(0),
          ),
        ),
      );

      // A fila é recarregada sempre, com ou sem toque no botão: quem está a
      // olhar para o terminal tem de ver a avaria nova sem ter de a pedir.
      await _recarregar(0);

      try {
        await _repo.marcarNotificacaoLida(notificacaoId);
      } catch (_) {
        // Falhar a marcação não pode repetir o aviso nem interromper o trabalho:
        // `_jaApresentadas` já garante que só aparece uma vez por sessão.
      }
    });
  }

  Future<void> _recarregar(int indice) async {
    final estado = _chaves[indice].currentState;
    if (estado is EcraRecarregavel) {
      await (estado as EcraRecarregavel).recarregar();
    }
  }

  static const List<({String titulo, IconData icone})> _menu = [
    (titulo: 'Fila de Avarias', icone: Icons.warning_amber_rounded),
    (titulo: 'As Minhas Intervenções', icone: Icons.history_toggle_off),
  ];

  void _selecionar(int indice, {bool fecharDrawer = false}) {
    final mudou = _indice != indice;
    setState(() => _indice = indice);

    if (fecharDrawer) Navigator.of(context).maybePop();

    if (!mudou) return;
    _recarregar(indice);
  }

  Future<void> _terminarSessao() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Terminar sessão?'),
        content: const Text(
          'Terá de voltar a autenticar-se para retomar as intervenções.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuar'),
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

    if (confirmado != true) return;

    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final identidade = _authService.identidadeParaCabecalho(
      nomeOmissao: 'Técnico',
      emailOmissao: 'sem email registado',
    );

    // Mesmo corte dos restantes shells (admin, operador, cliente): sidebar fixa
    // acima dele, drawer abaixo. O terminal do técnico era o único que ficava
    // sempre com a barra inferior, mesmo num ecrã de 1600 px.
    final bool eDesktop = context.ehAmplo;

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
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
                    Icons.engineering_rounded,
                    size: 20,
                    color: TemasCores.tecnicoAcento,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _menu[_indice].titulo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
      drawer: eDesktop
          ? null
          : Drawer(
              child: _barraLateral(identidade, dentroDrawer: true),
            ),
      body: Row(
        children: [
          if (eDesktop)
            SizedBox(
              width: 260,
              child: _barraLateral(identidade, dentroDrawer: false),
            ),
          Expanded(
            child: IndexedStack(
              index: _indice,
              children: [
                FilaManutencaoScreen(key: _chaves[0]),
                HistoricoTecnicoScreen(key: _chaves[1]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraLateral(
    ({String nome, String email}) identidade, {
    required bool dentroDrawer,
  }) {
    return Material(
      color: TemasCores.marcaEscura,
      child: SafeArea(
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
                        colors: [
                          TemasCores.tecnicoAcentoClaro,
                          TemasCores.tecnicoAcentoForte,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.engineering_rounded,
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
                          'Manutenção',
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
                  final selecionado = _indice == index;

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () =>
                            _selecionar(index, fecharDrawer: dentroDrawer),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: selecionado
                                ? TemasCores.tecnicoAcento
                                    .withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(
                              left: BorderSide(
                                color: selecionado
                                    ? TemasCores.tecnicoAcentoClaro
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
                                    ? TemasCores.tecnicoAcentoClaro
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
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: TemasCores.tecnicoAcentoClaro,
                          radius: 18,
                          child: Text(
                            obterIniciais(identidade.nome, omissao: 'TC'),
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
                                identidade.nome,
                                style: const TextStyle(
                                  color: TemasCores.textoInverso,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                identidade.email,
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
            ),
          ],
        ),
      ),
    );
  }
}
