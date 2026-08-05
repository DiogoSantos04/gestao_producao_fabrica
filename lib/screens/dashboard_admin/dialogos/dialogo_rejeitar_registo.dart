import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';

/// Confirmação de rejeição de um registo pendente.
///
/// Devolve `true` se o administrador confirmou. A conta não é apagada: passa a
/// "Inativo", o que preserva o registo para auditoria.
class DialogoRejeitarRegisto {
  const DialogoRejeitarRegisto._();

  static Future<bool> mostrar(BuildContext context, {required String nome}) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejeitar Registo'),
        content: Text(
          'Tem a certeza de que pretende rejeitar o registo de "$nome"?\n\n'
          'A conta ficará marcada como "Inativo" e o utilizador não poderá aceder à aplicação.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.erro, foregroundColor: TemasCores.textoInverso),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    return confirmar == true;
  }
}
