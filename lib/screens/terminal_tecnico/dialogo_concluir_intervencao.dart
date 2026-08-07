import 'package:flutter/material.dart';

import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/tecnico_repository.dart';

/// Relatório do técnico ao fechar uma intervenção.
///
/// É aqui que se preenche o que o administrador, até agora, tinha de escrever à
/// mão no Registo Técnico do painel — sobre um trabalho que não fez.
///
/// Devolve `true` quando a intervenção ficou fechada.
class DialogoConcluirIntervencao extends StatefulWidget {
  final IncidenciaModel incidencia;
  final TecnicoRepository repositorio;

  const DialogoConcluirIntervencao({
    super.key,
    required this.incidencia,
    required this.repositorio,
  });

  static Future<bool?> mostrar(
    BuildContext context, {
    required IncidenciaModel incidencia,
    required TecnicoRepository repositorio,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => DialogoConcluirIntervencao(
        incidencia: incidencia,
        repositorio: repositorio,
      ),
    );
  }

  @override
  State<DialogoConcluirIntervencao> createState() =>
      _DialogoConcluirIntervencaoState();
}

class _DialogoConcluirIntervencaoState
    extends State<DialogoConcluirIntervencao> {
  final _diagnosticoController = TextEditingController();
  final _acoesController = TextEditingController();
  final _pecasController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _aGravar = false;

  @override
  void dispose() {
    _diagnosticoController.dispose();
    _acoesController.dispose();
    _pecasController.dispose();
    super.dispose();
  }

  Future<void> _concluir() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _aGravar = true);
    try {
      await widget.repositorio.concluir(
        incidenciaId: widget.incidencia.id,
        diagnostico: _diagnosticoController.text.trim(),
        acoes: _acoesController.text.trim(),
        pecas: _pecasController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem('$e', eErro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incidencia = widget.incidencia;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.build_circle_rounded, color: TemasCores.avisoTextoForte),
          SizedBox(width: 8),
          Expanded(child: Text('Fechar Intervenção')),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: TemasCores.avisoFundo,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TemasCores.avisoBorda),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incidencia.rotulo ?? 'Manutenção requerida',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.avisoTextoForte,
                        ),
                      ),
                      // O sintoma que o operador descreveu é o ponto de partida
                      // do diagnóstico: sem ele à vista, o técnico teria de o ir
                      // procurar noutro ecrã.
                      if ((incidencia.descricaoOperador ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Relato do operador: ${incidencia.descricaoOperador!.trim()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TemasCores.avisoTexto,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextFormField(
                  controller: _diagnosticoController,
                  enabled: !_aGravar,
                  maxLines: 2,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Diagnóstico da avaria *',
                    hintText: 'Qual era a causa? Ex: rolamento do veio partido',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Indique a causa apurada.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _acoesController,
                  enabled: !_aGravar,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ações realizadas *',
                    hintText:
                        'O que foi feito para resolver: substituição, calibração, afinação…',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Descreva o trabalho efetuado.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pecasController,
                  enabled: !_aGravar,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Peças substituídas',
                    hintText: 'Opcional — deixe vazio se não aplicou material',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Ao fechar, a ordem fica a aguardar Line Clearance da '
                  'qualidade. A produção não retoma já.',
                  style: TextStyle(
                    fontSize: 11,
                    color: TemasCores.textoTerciario,
                  ),
                ),
              ],
            ),
          ),
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
          label: const Text('Concluir Intervenção'),
          onPressed: _aGravar ? null : _concluir,
        ),
      ],
    );
  }
}
