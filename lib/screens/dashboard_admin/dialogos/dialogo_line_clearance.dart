import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../repositories/encomendas_repository.dart';

/// Valida o line clearance (FAI) de uma ordem parada e retoma a produção.
///
/// Mostra o resumo da intervenção técnica já registada, para que quem aprova
/// veja o que foi feito antes de libertar a linha.
///
/// Devolve a mensagem de sucesso, ou `null` se o utilizador desistir.
class DialogoLineClearance extends StatefulWidget {
  /// Incidência ativa da ordem. Pode ser `null` — o botão continua visível e a
  /// falta de incidência é reportada como erro, tal como antes da extração.
  final Map<String, dynamic>? incidencia;

  final EncomendasRepository repositorio;

  const DialogoLineClearance({
    super.key,
    required this.incidencia,
    required this.repositorio,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required Map<String, dynamic>? incidencia,
    required EncomendasRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DialogoLineClearance(
        incidencia: incidencia,
        repositorio: repositorio,
      ),
    );
  }

  @override
  State<DialogoLineClearance> createState() => _DialogoLineClearanceState();
}

class _DialogoLineClearanceState extends State<DialogoLineClearance> {
  bool _aGravar = false;

  Future<void> _aprovar() async {
    setState(() => _aGravar = true);
    try {
      final incidencia = widget.incidencia;
      if (incidencia == null) {
        throw Exception('Não há incidência ativa para validar.');
      }

      // Fechar a incidência e libertar a ordem numa só transação.
      await widget.repositorio
          .aprovarLineClearance(int.parse(incidencia['id'].toString()));

      if (!mounted) return;
      Navigator.pop(context, '🟢 Line Clearance Aprovado! Produção retomada.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem(
        'Erro ao aprovar Line Clearance: ${mensagemDeErro(e)}',
        eErro: true,
      );
    }
  }

  /// Resumo do que a manutenção fez, em caixa própria.
  Widget _resumoIntervencao(Map<String, dynamic> incidencia) {
    const estilo = TextStyle(fontSize: 12, color: TemasCores.sucessoTextoIntenso);
    final notaTecnica = incidencia['nota_tecnica'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: TemasCores.sucessoFundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.sucessoBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumo da Intervenção Técnica:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: TemasCores.sucessoTextoIntenso,
            ),
          ),
          const SizedBox(height: 4),
          Text('Tipo: ${incidencia['tipo_manutencao'] ?? 'N/A'}', style: estilo),
          if (incidencia['tipo_manutencao'] == 'INTERNA')
            Text(
              'Técnico: ${incidencia['utilizadores']?['nome_utilizador'] ?? 'Técnico Interno'}',
              style: estilo,
            )
          else if (incidencia['tipo_manutencao'] == 'EXTERNA')
            Text(
              'Entidade: ${incidencia['entidade_externa'] ?? 'Empresa Externa'}',
              style: estilo,
            ),
          if (notaTecnica != null && notaTecnica.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Nota Técnica: $notaTecnica',
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: TemasCores.sucessoTextoForte,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final incidencia = widget.incidencia;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: TemasCores.sucessoTexto),
          SizedBox(width: 8),
          Flexible(child: Text('Aprovar Line Clearance (FAI)', overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: larguraDialogo(context, 450),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (incidencia != null) _resumoIntervencao(incidencia),
            const Text(
              'Confirmação de Qualidade:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 6),
            const Text(
              'Ao aprovar o Line Clearance, confirma que a 1ª peça (First Article '
              'Inspection) foi validada e a linha de produção está limpa e pronta '
              'a retomar.',
              style: TextStyle(fontSize: 11, color: TemasCores.textoApoioForte),
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
            backgroundColor: TemasCores.sucessoTexto,
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
              : const Icon(Icons.check_circle_rounded, size: 16),
          label: const Text('Validar & Libertar Linha'),
          onPressed: _aGravar ? null : _aprovar,
        ),
      ],
    );
  }
}
