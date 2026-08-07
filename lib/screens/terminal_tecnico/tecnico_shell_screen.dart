import 'dart:async';

import 'package:flutter/material.dart';

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

  void _selecionar(int indice) {
    final mudou = _indice != indice;
    setState(() => _indice = indice);

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

    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
      appBar: AppBar(
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
              color: TemasCores.avisoTexto,
            ),
            const SizedBox(width: 10),
            Text(_menu[_indice].titulo),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: TemasCores.avisoTexto,
                  child: Text(
                    obterIniciais(identidade.nome, omissao: 'TC'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: TemasCores.textoInverso,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  identidade.nome,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TemasCores.textoPrimario,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Terminar sessão',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _terminarSessao,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          FilaManutencaoScreen(key: _chaves[0]),
          HistoricoTecnicoScreen(key: _chaves[1]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: _selecionar,
        destinations: _menu
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icone),
                label: item.titulo,
              ),
            )
            .toList(),
      ),
    );
  }
}
