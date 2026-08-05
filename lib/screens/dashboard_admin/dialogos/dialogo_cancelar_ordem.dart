import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';

/// Pede confirmação e motivo para cancelar uma ordem.
///
/// Devolve o motivo escrito, ou `null` se o utilizador desistir. Não escreve
/// nada: o cancelamento é feito por quem a abre, que também trata do estado de
/// carregamento do ecrã.
class DialogoCancelarOrdem extends StatefulWidget {
  /// Referência legível da ordem (por exemplo `ORD-2026-0042`).
  final String referencia;

  const DialogoCancelarOrdem({super.key, required this.referencia});

  static Future<String?> mostrar(
    BuildContext context, {
    required String referencia,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DialogoCancelarOrdem(referencia: referencia),
    );
  }

  @override
  State<DialogoCancelarOrdem> createState() => _DialogoCancelarOrdemState();
}

class _DialogoCancelarOrdemState extends State<DialogoCancelarOrdem> {
  final _motivoController = TextEditingController();

  @override
  void dispose() {
    _motivoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motivo = _motivoController.text.trim();

    return AlertDialog(
      title: const Text('Cancelar Ordem de Produção'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A ordem ${widget.referencia} será marcada como cancelada. O histórico de '
              'produção e as incidências são preservados para auditoria.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _motivoController,
              maxLines: 2,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo do cancelamento *',
                hintText: 'Ex: Anulação a pedido do cliente.',
                border: OutlineInputBorder(),
              ),
              // Redesenha para ativar o botão assim que houver texto.
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Não'),
        ),
        ElevatedButton(
          onPressed: motivo.isEmpty ? null : () => Navigator.pop(context, motivo),
          style: ElevatedButton.styleFrom(
            backgroundColor: TemasCores.erro,
            foregroundColor: TemasCores.textoInverso,
          ),
          child: const Text('Sim, Cancelar'),
        ),
      ],
    );
  }
}
