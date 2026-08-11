import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../models/encomenda_model.dart';
import '../../../models/reason_code_model.dart';
import '../../../repositories/encomendas_repository.dart';

/// Suspende uma ordem em produção, registando o motivo oficial da paragem.
///
/// Devolve a mensagem de sucesso a apresentar pelo ecrã, ou `null` se o
/// utilizador desistir. Quem chama recarrega a lista quando o resultado não for
/// nulo — a suspensão muda o estado da ordem no servidor.
class DialogoWipHold extends StatefulWidget {
  final EncomendaModel encomenda;
  final List<ReasonCodeModel> reasonCodes;
  final EncomendasRepository repositorio;

  const DialogoWipHold({
    super.key,
    required this.encomenda,
    required this.reasonCodes,
    required this.repositorio,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required EncomendaModel encomenda,
    required List<ReasonCodeModel> reasonCodes,
    required EncomendasRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DialogoWipHold(
        encomenda: encomenda,
        reasonCodes: reasonCodes,
        repositorio: repositorio,
      ),
    );
  }

  @override
  State<DialogoWipHold> createState() => _DialogoWipHoldState();
}

class _DialogoWipHoldState extends State<DialogoWipHold> {
  final _notasController = TextEditingController();
  int? _reasonCodeId;
  bool _aGravar = false;

  @override
  void dispose() {
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _aplicar() async {
    if (_reasonCodeId == null) {
      context.mostrarMensagem('Selecione um motivo de paragem.', eErro: true);
      return;
    }

    setState(() => _aGravar = true);
    try {
      // Criar a incidência e suspender a ordem é uma só transação — e o posto de
      // trabalho é resolvido no servidor a partir da fase atual.
      await widget.repositorio.aplicarWipHold(
        encomendaId: widget.encomenda.id,
        reasonCodeId: _reasonCodeId!,
        descricaoOperador: _notasController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, '🔴 Ordem colocada em ON HOLD!');
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem(
        'Erro ao aplicar WIP Hold: ${mensagemDeErro(e)}',
        eErro: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.pause_circle_filled_rounded, color: TemasCores.erroTexto),
          SizedBox(width: 8),
          Flexible(child: Text('Suspender Ordem (WIP Hold)', overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: larguraDialogo(context, 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione o motivo oficial (Reason Code) da paragem na linha:',
              style: TextStyle(fontSize: 12, color: TemasCores.textoApoio),
            ),
            const SizedBox(height: 12),
            // A deduplicação por `id` é feita no repositório: o dropdown lança
            // em runtime com dois itens de igual valor.
            DropdownButtonFormField<int>(
              initialValue: _reasonCodeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Reason Code *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: widget.reasonCodes.map((r) {
                return DropdownMenuItem<int>(
                  value: r.id,
                  child: Text(r.rotulo, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged:
                  _aGravar ? null : (val) => setState(() => _reasonCodeId = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasController,
              enabled: !_aGravar,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descrição / Observações do Operador',
                hintText: 'Ex: Frequência de ruído anormal no equipamento.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _aGravar ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: TemasCores.erroTexto,
            foregroundColor: TemasCores.textoInverso,
          ),
          icon: _aGravar
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: TemasCores.textoInverso,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.block, size: 16),
          label: const Text('Aplicar WIP Hold'),
          onPressed: _aGravar ? null : _aplicar,
        ),
      ],
    );
  }
}
