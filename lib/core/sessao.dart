import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import 'sessao_local.dart';
import 'temas_cores.dart';

/// Encaminha para o login quando a sessão se perde sem ser a pedido.
///
/// Antes disto, ninguém subscrevia `onAuthStateChange`. Se o token expirasse ou
/// o administrador desativasse a conta a meio do turno, a aplicação ficava a
/// mostrar os dados em cache e a falhar em silêncio nas queries seguintes — o
/// utilizador via um ecrã que já não correspondia a nada e não tinha forma de
/// perceber que precisava de voltar a entrar.
///
/// O travão de `estado_conta` do [AuthService] continua a existir, mas só corre
/// no login e no arranque; isto cobre o resto do tempo.
class VigilanteSessao {
  VigilanteSessao({
    required this.chaveNavegador,
    required this.chaveMensagens,
  });

  final GlobalKey<NavigatorState> chaveNavegador;
  final GlobalKey<ScaffoldMessengerState> chaveMensagens;

  StreamSubscription<AuthState>? _subscricao;

  void iniciar() {
    _subscricao ??= Supabase.instance.client.auth.onAuthStateChange.listen(
      (estado) {
        if (estado.event == AuthChangeEvent.signedOut) {
          _tratarSessaoTerminada();
        }
      },
      // Uma falha no próprio canal de eventos não pode derrubar a aplicação.
      onError: (_) {},
    );
  }

  void descartar() {
    _subscricao?.cancel();
    _subscricao = null;
  }

  void _tratarSessaoTerminada() {
    // Logout carregado no botão: os ecrãs já tratam da navegação.
    if (SessaoLocal.consumirTerminoIntencional()) return;

    final navegador = chaveNavegador.currentState;
    if (navegador == null) return;

    navegador.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );

    chaveMensagens.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('A sua sessão terminou. Inicie sessão novamente.'),
          backgroundColor: TemasCores.vermelhoErro,
        ),
      );
  }
}
