import 'package:flutter/material.dart';

import '../../../models/encomenda_model.dart';
import '../../../models/fase_model.dart';

/// O que o utilizador escolheu no [DialogoEditarOrdem].
///
/// [faseAtualId] a `null` significa "dar como concluída" — é o mesmo valor que
/// a coluna `fase_atual_id` guarda para uma ordem terminada.
class EdicaoOrdem {
  final String dataEntrega;
  final int? faseAtualId;

  const EdicaoOrdem({required this.dataEntrega, required this.faseAtualId});
}

/// Altera o prazo e a fase atual de uma ordem.
///
/// Devolve a [EdicaoOrdem] escolhida, ou `null` se o utilizador desistir. A
/// gravação fica a cargo de quem o abre.
class DialogoEditarOrdem extends StatefulWidget {
  final EncomendaModel encomenda;

  /// Roteiro do produto da ordem, já carregado pelo ecrã.
  final List<FaseModel> fases;

  const DialogoEditarOrdem({
    super.key,
    required this.encomenda,
    required this.fases,
  });

  static Future<EdicaoOrdem?> mostrar(
    BuildContext context, {
    required EncomendaModel encomenda,
    required List<FaseModel> fases,
  }) {
    return showDialog<EdicaoOrdem>(
      context: context,
      builder: (_) => DialogoEditarOrdem(encomenda: encomenda, fases: fases),
    );
  }

  @override
  State<DialogoEditarOrdem> createState() => _DialogoEditarOrdemState();
}

class _DialogoEditarOrdemState extends State<DialogoEditarOrdem> {
  late final TextEditingController _dataController =
      TextEditingController(text: widget.encomenda.dataEntregaIso ?? '');
  late int? _faseId = widget.encomenda.faseAtualId;

  @override
  void dispose() {
    _dataController.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final data = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dataController.text) ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (data == null) return;
    setState(() {
      _dataController.text =
          "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Formulário com campos de texto: o teclado do telemóvel come mais de
      // metade da altura e o conteúdo tem de poder deslizar.
      scrollable: true,
      title: const Text('Editar Ordem de Produção'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _dataController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Data de Entrega (AAAA-MM-DD)',
              suffixIcon: Icon(Icons.calendar_today),
            ),
            onTap: _escolherData,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _faseId,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Fase Atual de Produção'),
            items: [
              ...widget.fases.map((f) {
                return DropdownMenuItem<int?>(
                  value: f.id,
                  child: Text('Fase ${f.ordem}: ${f.nomeFasePadrao}', maxLines: 1, overflow: TextOverflow.ellipsis),
                );
              }),
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('🏁 Dar como Concluída'),
              ),
            ],
            onChanged: (val) => setState(() => _faseId = val),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            EdicaoOrdem(
              dataEntrega: _dataController.text.trim(),
              faseAtualId: _faseId,
            ),
          ),
          child: const Text('Gravar'),
        ),
      ],
    );
  }
}
