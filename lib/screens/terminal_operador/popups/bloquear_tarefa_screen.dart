import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/temas_cores.dart';

class BloquearTarefaPopup extends StatefulWidget {
  final int encomendaId;
  final String codigoRastreio;
  final int faseAtualId;

  const BloquearTarefaPopup({
    super.key,
    required this.encomendaId,
    required this.codigoRastreio,
    required this.faseAtualId,
  });

  @override
  State<BloquearTarefaPopup> createState() => _BloquearTarefaPopupState();
}

class _BloquearTarefaPopupState extends State<BloquearTarefaPopup> {
  final _supabase = Supabase.instance.client;
  final _motivoController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void dispose() {
    _motivoController.dispose();
    super.dispose();
  }

  // RF010: Cria um log no histórico e vincula a incidência usando as colunas exatas do ER
  Future<void> _submeterIncidencia() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final utilizadorId = _supabase.auth.currentUser?.id;

      // 1. Criar um registo em 'historico_producao' para servir de âncora à incidência
      final historicoData = await _supabase.from('historico_producao').insert({
        'encomenda_id': widget.encomendaId,
        'fase_concluida_id': widget.faseAtualId, // Mantém o estado da fase onde ocorreu o erro
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      }).select('id').single();

      final int historicoId = historicoData['id'];

      // 2. Inserir na tabela 'incidencias' usando 'motivo' e 'historico_producao_id'
      await _supabase.from('incidencias').insert({
        'motivo': _motivoController.text.trim(),
        'historico_producao_id': historicoId,
        'data_regist_': DateTime.now().toIso8601String(), // mapeado conforme o vosso data_registo
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incidência registada para a encomenda ${widget.codigoRastreio}!'),
            backgroundColor: TemasCores.vermelhoErro,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao bloquear: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          Expanded(child: Text('Bloquear ${widget.codigoRastreio}')),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Descreva o motivo da paragem operacional no chão de fábrica.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motivoController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo da Incidência',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Descreva o motivo' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submeterIncidencia,
          style: ElevatedButton.styleFrom(backgroundColor: TemasCores.vermelhoErro, foregroundColor: Colors.white),
          child: _isSaving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Bloquear Produção'),
        ),
      ],
    );
  }
}