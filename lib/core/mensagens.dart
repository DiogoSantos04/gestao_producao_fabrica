import 'package:flutter/material.dart';

import '../repositories/base_repository.dart';
import 'temas_cores.dart';

/// Texto legível de um erro, para SnackBars.
///
/// Os repositórios já devolvem mensagens de negócio prontas a mostrar; das
/// exceções genéricas só se remove o prefixo `Exception: `.
String mensagemDeErro(Object e) {
  if (e is RepositoryException) return e.mensagem;
  return e.toString().replaceAll('Exception: ', '');
}

/// Ponto único para apresentar SnackBars, evitando repetir o mesmo bloco
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` em cada ecrã.
///
/// O `mounted` continua a ser responsabilidade de quem chama, tal como antes.
extension MensagensContexto on BuildContext {
  /// SnackBar com a cor padrão de sucesso/erro do tema.
  void mostrarMensagem(String msg, {bool eErro = false, Duration? duracao}) {
    mostrarSnack(
      msg,
      cor: eErro ? TemasCores.vermelhoErro : TemasCores.verdeSucesso,
      duracao: duracao,
    );
  }

  /// SnackBar com cor arbitrária. Se [cor] for nula usa a cor padrão do tema.
  void mostrarSnack(String msg, {Color? cor, Duration? duracao}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: cor,
        duration: duracao ?? const Duration(seconds: 4),
      ),
    );
  }
}
