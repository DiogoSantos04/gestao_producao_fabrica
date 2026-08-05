import 'package:flutter/material.dart';

import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../repositories/encomendas_repository.dart';

/// Fecha uma intervenção técnica sobre uma incidência aberta.
///
/// A intervenção pode ser interna (com técnico da casa) ou externa (com empresa
/// de assistência) — os campos obrigatórios mudam com essa escolha.
///
/// Devolve a mensagem de sucesso, ou `null` se o utilizador desistir.
class DialogoRegistoTecnico extends StatefulWidget {
  /// Linha da incidência ativa; só se usam `id` e `motivo`.
  final Map<String, dynamic> incidencia;

  /// Técnicos internos elegíveis, com `utilizador_id`, `nome_utilizador` e `perfil`.
  final List<Map<String, dynamic>> tecnicos;

  final EncomendasRepository repositorio;

  const DialogoRegistoTecnico({
    super.key,
    required this.incidencia,
    required this.tecnicos,
    required this.repositorio,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required Map<String, dynamic> incidencia,
    required List<Map<String, dynamic>> tecnicos,
    required EncomendasRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DialogoRegistoTecnico(
        incidencia: incidencia,
        tecnicos: tecnicos,
        repositorio: repositorio,
      ),
    );
  }

  @override
  State<DialogoRegistoTecnico> createState() => _DialogoRegistoTecnicoState();
}

class _DialogoRegistoTecnicoState extends State<DialogoRegistoTecnico> {
  final _entidadeExternaController = TextEditingController();
  final _notaTecnicaController = TextEditingController();

  String _tipoManutencao = 'INTERNA'; // 'INTERNA' ou 'EXTERNA'
  String? _tecnicoId;
  bool _aGravar = false;

  bool get _eInterna => _tipoManutencao == 'INTERNA';

  @override
  void dispose() {
    _entidadeExternaController.dispose();
    _notaTecnicaController.dispose();
    super.dispose();
  }

  Future<void> _concluir() async {
    if (_eInterna && _tecnicoId == null) {
      context.mostrarMensagem('Selecione o técnico interno responsável.', eErro: true);
      return;
    }
    if (!_eInterna && _entidadeExternaController.text.trim().isEmpty) {
      context.mostrarMensagem('Indique a empresa de assistência externa.', eErro: true);
      return;
    }

    setState(() => _aGravar = true);
    try {
      await widget.repositorio.registarIntervencaoTecnica(
        incidenciaId: int.parse(widget.incidencia['id'].toString()),
        tipoManutencao: _tipoManutencao,
        tecnicoId: _eInterna ? _tecnicoId : null,
        entidadeExterna:
            _eInterna ? null : _entidadeExternaController.text.trim(),
        notaTecnica: _notaTecnicaController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        '🛠️ Registo técnico concluído! A ordem aguarda agora Line Clearance.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem(
        'Erro ao gravar registo técnico: ${mensagemDeErro(e)}',
        eErro: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.build_circle_rounded, color: TemasCores.avisoTextoForte),
          const SizedBox(width: 8),
          const Text('Registo Técnico de Intervenção'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: TemasCores.avisoFundo,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TemasCores.avisoBorda),
              ),
              child: Text(
                'Incidente: ${widget.incidencia['motivo'] ?? 'Manutenção Requerida'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.avisoTextoForte,
                ),
              ),
            ),
            const Text(
              'Tipo de Intervenção Técnica:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'INTERNA',
                  label: Text('Manutenção Interna'),
                  icon: Icon(Icons.engineering_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'EXTERNA',
                  label: Text('Assistência Externa'),
                  icon: Icon(Icons.fire_truck_rounded, size: 16),
                ),
              ],
              selected: {_tipoManutencao},
              onSelectionChanged: _aGravar
                  ? null
                  : (nova) => setState(() => _tipoManutencao = nova.first),
            ),
            const SizedBox(height: 16),
            if (_eInterna) ...[
              DropdownButtonFormField<String>(
                value: _tecnicoId,
                decoration: const InputDecoration(
                  labelText: 'Técnico Responsável *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.tecnicos.map((u) {
                  final id = u['utilizador_id'].toString();
                  final nome = u['nome_utilizador'] ?? 'Sem nome';
                  final perfil = u['perfil'] ?? 'Utilizador';
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text('$nome ($perfil)',
                        style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged:
                    _aGravar ? null : (val) => setState(() => _tecnicoId = val),
              ),
            ] else ...[
              TextField(
                controller: _entidadeExternaController,
                enabled: !_aGravar,
                decoration: const InputDecoration(
                  labelText: 'Empresa / Entidade Externa *',
                  hintText: 'Ex: Siemens, Kuka Robotics, EletroCaldas',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _notaTecnicaController,
              enabled: !_aGravar,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Relatório Técnico / Ações Corretivas',
                hintText:
                    'Descreva os trabalhos efetuados, peças substituídas ou calibração efetuada...',
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
            backgroundColor: TemasCores.avisoTexto,
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
              : const Icon(Icons.check_circle_outline, size: 16),
          label: const Text('Concluir Intervenção Técnica'),
          onPressed: _aGravar ? null : _concluir,
        ),
      ],
    );
  }
}
