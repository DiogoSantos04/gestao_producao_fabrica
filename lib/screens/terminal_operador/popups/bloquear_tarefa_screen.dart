import 'package:flutter/material.dart';

import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../models/reason_code_model.dart';
import '../../../repositories/base_repository.dart';
import '../../../repositories/encomendas_repository.dart';
import '../../../widgets/estado_erro.dart';

/// Registo de uma paragem de linha pelo operador (WIP Hold).
///
/// A suspensão passa pela RPC transacional `aplicar_wip_hold`, a mesma que o
/// painel de controlo usa. Antes, este ecrã fazia duas escritas soltas e
/// **nunca** colocava `encomendas.em_suspenso = true`: o botão "Bloquear
/// Produção" criava a incidência mas deixava a ordem a fluir para o admin e
/// para os postos seguintes. Ver bugs (B), (C) e (D) em docs/AlteracoesNoOperador.md.
///
/// O `historico_producao_id` deixou de ser fabricado aqui. Para obter um, o
/// ecrã inseria um registo com `data_conclusao = agora` para uma fase que não
/// tinha sido concluída — esse registo falso era depois contado como fase
/// executada no histórico do operador, nos relatórios de turno e nas métricas
/// do admin. A RPC resolve a ligação no servidor, a partir da fase atual.
class BloquearTarefaPopup extends StatefulWidget {
  final int encomendaId;
  final String codigoRastreio;
  final int faseAtualId;

  /// Observações pré-preenchidas.
  ///
  /// Serve o caminho que vem da checklist Poka-Yoke: um ponto de controlo não
  /// conforme não fecha a fase, abre uma incidência, e o texto do ponto que
  /// falhou chega já escrito para o operador não o reescrever de memória.
  final String? descricaoInicial;

  const BloquearTarefaPopup({
    super.key,
    required this.encomendaId,
    required this.codigoRastreio,
    required this.faseAtualId,
    this.descricaoInicial,
  });

  @override
  State<BloquearTarefaPopup> createState() => _BloquearTarefaPopupState();
}

class _BloquearTarefaPopupState extends State<BloquearTarefaPopup> {
  final EncomendasRepository _encomendasRepo = EncomendasRepository();
  final _observacoesController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Motivos oficiais de paragem, vindos da tabela `reason_codes`.
  ///
  /// Substituem a lista de cinco strings que estava escrita em Dart e era
  /// concatenada no campo de texto (`'[Motivo] observações'`). Sem código
  /// estruturado, uma análise de Pareto das paragens era impossível.
  List<ReasonCodeModel> _reasonCodes = [];
  int? _reasonCodeSelecionado;

  bool _aCarregarMotivos = true;
  String? _erroMotivos;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final inicial = widget.descricaoInicial;
    if (inicial != null && inicial.isNotEmpty) {
      _observacoesController.text = inicial;
    }
    _carregarMotivos();
  }

  @override
  void dispose() {
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _carregarMotivos() async {
    if (mounted) {
      setState(() {
        _aCarregarMotivos = true;
        _erroMotivos = null;
      });
    }

    try {
      // O repositório já devolve a lista deduplicada por `id`: o dropdown
      // rebenta em runtime se receber dois itens com o mesmo valor.
      final motivos = await _encomendasRepo.obterReasonCodes();
      if (!mounted) return;
      setState(() {
        _reasonCodes = motivos;
        _aCarregarMotivos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroMotivos = _mensagemDeErro(e);
        _aCarregarMotivos = false;
      });
    }
  }

  String _mensagemDeErro(Object e) {
    if (e is RepositoryException) return e.mensagem;
    return descreverErro(e);
  }

  Future<void> _submeterIncidencia() async {
    if (!_formKey.currentState!.validate()) return;
    if (_reasonCodeSelecionado == null) return;

    setState(() => _isSaving = true);

    try {
      // Criar a incidência e suspender a ordem é uma só transação; o posto de
      // trabalho é resolvido no servidor a partir da fase atual da encomenda.
      await _encomendasRepo.aplicarWipHold(
        encomendaId: widget.encomendaId,
        reasonCodeId: _reasonCodeSelecionado!,
        descricaoOperador: _observacoesController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Retorna true para atualizar o ecrã anterior
      }
    } catch (e) {
      if (mounted) {
        context.mostrarMensagem(
          'Não foi possível bloquear: ${_mensagemDeErro(e)}',
          eErro: true,
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool podeSubmeter =
        !_isSaving && !_aCarregarMotivos && _erroMotivos == null && _reasonCodes.isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      actionsPadding: const EdgeInsets.all(24),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: TemasCores.erroFundo,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: TemasCores.erroMedio,
              size: 24,
            ),
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
            // Campo de Motivo (Reason Code oficial)
            const Text(
              'Motivo *',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            _construirCampoMotivo(),
            const SizedBox(height: 16),

            // Campo de Observações (Multilinha)
            const Text(
              'Observações *',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _observacoesController,
              maxLines: 4,
              enabled: !_isSaving,
              decoration: InputDecoration(
                hintText: 'Descreva detalhadamente a incidência...',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: TemasCores.textoDesativado,
                ),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: TemasCores.bordaForte),
                ),
              ),
              validator: (val) =>
                  (val == null || val.trim().isEmpty) ? 'Por favor, detalhe o problema.' : null,
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
                  side: const BorderSide(color: TemasCores.borda),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  backgroundColor: TemasCores.superficieTenue,
                ),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(
                    color: TemasCores.textoSecundario,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Botão Bloquear Produção
            Expanded(
              child: ElevatedButton(
                onPressed: podeSubmeter ? _submeterIncidencia : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: TemasCores.erroClaro,
                  foregroundColor: TemasCores.erroTextoIntenso,
                  disabledBackgroundColor: TemasCores.superficieInerte,
                  disabledForegroundColor: TemasCores.textoTerciario,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TemasCores.erroTextoIntenso,
                        ),
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

  /// Dropdown dos reason codes, com os estados de carregamento e de falha
  /// visíveis. Uma falha ao ler a tabela não pode passar por "não há motivos":
  /// sem motivo não há bloqueio possível e o operador tem de o saber.
  Widget _construirCampoMotivo() {
    if (_aCarregarMotivos) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TemasCores.bordaForte),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'A carregar motivos de paragem…',
              style: TextStyle(fontSize: 13, color: TemasCores.textoApoio),
            ),
          ],
        ),
      );
    }

    if (_erroMotivos != null || _reasonCodes.isEmpty) {
      final String texto = _erroMotivos ??
          'Não existem motivos de paragem configurados. Contacte a supervisão.';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TemasCores.erroFundo,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: TemasCores.erroBorda),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline,
              size: 18,
              color: TemasCores.erroMedio,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  fontSize: 12,
                  color: TemasCores.erroTextoIntenso,
                ),
              ),
            ),
            if (_erroMotivos != null)
              TextButton(
                onPressed: _carregarMotivos,
                child: const Text(
                  'Tentar de novo',
                  style: TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<int>(
      initialValue: _reasonCodeSelecionado,
      hint: const Text('Selecione um motivo', style: TextStyle(fontSize: 14)),
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: TemasCores.bordaForte),
        ),
      ),
      items: _reasonCodes.map((r) {
        return DropdownMenuItem<int>(
          value: r.id,
          child: Text(
            r.rotulo,
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      validator: (val) => val == null ? 'Por favor, selecione um motivo.' : null,
      onChanged:
          _isSaving ? null : (val) => setState(() => _reasonCodeSelecionado = val),
    );
  }
}
