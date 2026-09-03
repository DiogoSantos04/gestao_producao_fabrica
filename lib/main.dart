import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'core/sessao.dart';
import 'core/supabase_config.dart';
import 'core/temas_cores.dart';
import 'screens/login_screen.dart';
import 'screens/portal_cliente/rastreio_cliente_screen.dart';

/// Navegador global.
///
/// Necessário para as ações que não partem de um ecrã concreto — em particular,
/// o encaminhamento para o login quando a sessão se perde (ver [VigilanteSessao]).
final GlobalKey<NavigatorState> chaveNavegador = GlobalKey<NavigatorState>();

/// Mensagens (SnackBars) que sobrevivem a uma troca de ecrã.
final GlobalKey<ScaffoldMessengerState> chaveMensagens =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Substitui o ecrã vermelho do Flutter por algo legível. Um erro de build num
  // painel não deve mostrar uma stack trace a quem está na fábrica.
  ErrorWidget.builder = (detalhes) => _EcraErroInesperado(detalhes: detalhes);

  final anterior = FlutterError.onError;
  FlutterError.onError = (detalhes) {
    anterior?.call(detalhes);
    debugPrint('Erro não tratado: ${detalhes.exceptionAsString()}');
  };

  // A inicialização do Supabase é aguardada antes do primeiro frame, pelo que
  // uma falha aqui — rede indisponível no arranque, por exemplo — deixava a
  // aplicação a morrer com ecrã preto, sem nada que explicasse porquê.
  try {
    await SupabaseConfig.init();
  } catch (e) {
    runApp(_AppArranqueFalhado(erro: e.toString()));
    return;
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final VigilanteSessao _vigilante = VigilanteSessao(
    chaveNavegador: chaveNavegador,
    chaveMensagens: chaveMensagens,
  );

  @override
  void initState() {
    super.initState();
    _vigilante.iniciar();

    // O rastreio fica empilhado sobre o login, e não no lugar dele, para quem
    // chega pela ligação do email poder recuar e entrar na conta a partir daí.
    final codigo = _codigoRastreioDoEndereco();
    if (codigo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chaveNavegador.currentState?.push(
          MaterialPageRoute(
            builder: (_) => RastreioClienteScreen(codigoInicial: codigo),
          ),
        );
      });
    }
  }

  /// Código de rastreio pedido no endereço (`?codigo=TRC-XXXXXX`).
  ///
  /// É a ligação que o email de arranque da produção leva. Fora da web,
  /// [Uri.base] não tem parâmetros e isto não faz nada.
  static String? _codigoRastreioDoEndereco() {
    final valor = Uri.base.queryParameters['codigo']?.trim();
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  @override
  void dispose() {
    _vigilante.descartar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Controlo de Produção',
      debugShowCheckedModeBanner: false,
      navigatorKey: chaveNavegador,
      scaffoldMessengerKey: chaveMensagens,
      theme: TemasCores.obterTema(),
      home: const LoginScreen(),
    );
  }
}

/// Mostrado quando a aplicação não consegue sequer arrancar.
///
/// Não usa [TemasCores] nem nada que dependa da inicialização: a esta altura
/// não há garantia nenhuma sobre o que está pronto.
class _AppArranqueFalhado extends StatelessWidget {
  const _AppArranqueFalhado({required this.erro});

  final String erro;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.redAccent),
                const SizedBox(height: 20),
                const Text(
                  'Não foi possível ligar ao servidor',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verifique a ligação à rede e volte a abrir a aplicação.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  Text(
                    erro,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Substitui o ecrã vermelho de erro do Flutter em release.
class _EcraErroInesperado extends StatelessWidget {
  const _EcraErroInesperado({required this.detalhes});

  final FlutterErrorDetails detalhes;

  @override
  Widget build(BuildContext context) {
    // Em desenvolvimento o ecrã vermelho é útil e deve manter-se.
    if (kDebugMode) return ErrorWidget(detalhes.exception);

    return const Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange),
              SizedBox(height: 12),
              Text(
                'Ocorreu um erro inesperado nesta secção.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
