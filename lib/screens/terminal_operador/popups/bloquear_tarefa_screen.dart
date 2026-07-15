import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _observacoesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  String? _motivoSelecionado;
  bool _isSaving = false;

  final List<String> _motivos = [
    'Avaria de Máquina',
    'Falta de Matéria-Prima',
    'Ausência de Operador',
    'Defeito de Qualidade',
    'Outro',
  ];

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _submeterIncidencia() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final utilizadorId = _supabase.auth.currentUser?.id;

      // 1. Criar um registo em 'historico_producao' para vincular à incidência
      final historicoData = await _supabase.from('historico_producao').insert({
        'encomenda_id': widget.encomendaId,
        'fase_concluida_id': widget.faseAtualId,
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      }).select('id').single();

      final int historicoId = historicoData['id'];

      // Concatenamos o Motivo com as Observações para guardar na vossa coluna 'motivo'
      final String motivoCompleto = '[$_motivoSelecionado] ${_observacoesController.text.trim()}';

      // 2. Inserir na tabela 'incidencias' com o nome exato da coluna: 'data_registo'
      await _supabase.from('incidencias').insert({
        'motivo': motivoCompleto,
        'historico_producao_id': historicoId,
        'data_registo': DateTime.now().toIso8601String(), // CORRIGIDO: de 'data_regist_' para 'data_registo'
      });

      if (mounted) {
        Navigator.of(context).pop(true); // Retorna true para atualizar o ecrã anterior
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 24),
          ),
          const SizedBox(width: 12),
          const Text(
            'Registar Bloqueio',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Campo de Motivo (Dropdown)
            const Text(
              'Motivo *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _motivoSelecionado,
              hint: const Text('Selecione um motivo', style: TextStyle(fontSize: 14)),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              items: _motivos.map((m) {
                return DropdownMenuItem<String>(
                  value: m,
                  child: Text(m, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              validator: (val) => val == null ? 'Por favor, selecione um motivo.' : null,
              onChanged: (val) => setState(() => _motivoSelecionado = val),
            ),
            const SizedBox(height: 16),

            // Campo de Observações (Multilinha)
            const Text(
              'Observações *',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _observacoesController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Descreva detalhadamente a incidência...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              validator: (val) => (val == null || val.trim().isEmpty) ? 'Por favor, detalhe o problem.' : null,
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            // Botão Cancelar
            Expanded(
              child: OutlinedButton(
                onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: Colors.grey.shade200),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  backgroundColor: Colors.grey.shade50,
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Botão Bloquear Produção
            Expanded(
              child: ElevatedButton(
                onPressed: _isSaving ? null : _submeterIncidencia,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFFFCA5A5),
                  foregroundColor: Colors.red.shade900,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Bloquear Produção',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}