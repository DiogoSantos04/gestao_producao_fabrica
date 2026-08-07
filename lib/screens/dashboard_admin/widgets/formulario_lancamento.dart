import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';

/// Níveis de prioridade que uma ordem de produção pode ter.
const List<String> niveisPrioridade = ['Normal', 'Urgente', 'Crítica'];

/// Formulário de lançamento de uma ordem de produção.
///
/// Estava num método de 401 linhas dentro do ecrã. Cada campo é agora um widget
/// próprio; o estado continua no ecrã, que é quem sabe gravar.
class FormularioLancamento extends StatelessWidget {
  const FormularioLancamento({
    super.key,
    required this.formKey,
    required this.clientes,
    required this.tiposProduto,
    required this.clienteSelecionado,
    required this.tipoProdutoSelecionado,
    required this.prioridadeSelecionada,
    required this.dataEntregaController,
    required this.quantidadeController,
    required this.requisitosQualidadeController,
    required this.pedidoSelecionadoId,
    required this.observacoesPedido,
    required this.isSaving,
    required this.aoMudarCliente,
    required this.aoMudarTipoProduto,
    required this.aoMudarPrioridade,
    required this.aoEscolherData,
    required this.aoLimparSelecao,
    required this.aoLancar,
  });

  final GlobalKey<FormState> formKey;
  final List<ClienteModel> clientes;
  final List<Map<String, dynamic>> tiposProduto;

  final String? clienteSelecionado;
  final String? tipoProdutoSelecionado;
  final String prioridadeSelecionada;

  final TextEditingController dataEntregaController;
  final TextEditingController quantidadeController;
  final TextEditingController requisitosQualidadeController;

  /// Pedido da App que originou este lançamento, ou `null` em entrada manual.
  final int? pedidoSelecionadoId;
  final String? observacoesPedido;

  final bool isSaving;

  final ValueChanged<String?> aoMudarCliente;
  final ValueChanged<String?> aoMudarTipoProduto;
  final ValueChanged<String> aoMudarPrioridade;
  final VoidCallback aoEscolherData;
  final VoidCallback aoLimparSelecao;
  final VoidCallback aoLancar;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cabecalho(
                vinculadoAPedido: pedidoSelecionadoId != null,
                aoLimparSelecao: aoLimparSelecao,
              ),
              const SizedBox(height: 24),
              if (pedidoSelecionadoId != null) ...[
                _FaixaPedidoVinculado(
                  pedidoId: pedidoSelecionadoId!,
                  observacoes: observacoesPedido,
                ),
                const SizedBox(height: 20),
              ],
              _CampoCliente(
                clientes: clientes,
                selecionado: clienteSelecionado,
                aoMudar: aoMudarCliente,
              ),
              const SizedBox(height: 20),
              _CampoTipoProduto(
                tiposProduto: tiposProduto,
                selecionado: tipoProdutoSelecionado,
                aoMudar: aoMudarTipoProduto,
              ),
              const SizedBox(height: 20),
              _CamposPrazoEQuantidade(
                dataEntregaController: dataEntregaController,
                quantidadeController: quantidadeController,
                aoEscolherData: aoEscolherData,
              ),
              const SizedBox(height: 20),
              _CampoPrioridade(
                selecionada: prioridadeSelecionada,
                aoMudar: aoMudarPrioridade,
              ),
              const SizedBox(height: 20),
              _CampoRequisitosQualidade(controller: requisitosQualidadeController),
              const SizedBox(height: 32),
              _BotaoLancar(
                isSaving: isSaving,
                vinculadoAPedido: pedidoSelecionadoId != null,
                aoLancar: aoLancar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decoração comum a todos os campos do formulário.
InputDecoration _decoracaoCampo({String? hintText, Widget? suffixIcon, EdgeInsets? padding}) {
  return InputDecoration(
    hintText: hintText,
    suffixIcon: suffixIcon,
    fillColor: TemasCores.superficieSuave,
    filled: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
  );
}

/// Rótulo por cima de cada campo.
class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.vinculadoAPedido, required this.aoLimparSelecao});

  final bool vinculadoAPedido;
  final VoidCallback aoLimparSelecao;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lançar Nova Encomenda',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            ),
            const SizedBox(height: 4),
            Text(
              vinculadoAPedido
                  ? 'Agendando pedido vindo da Aplicação B2B'
                  : 'Preencha os dados para iniciar uma nova ordem de produção',
              style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
            ),
          ],
        ),
        if (vinculadoAPedido)
          TextButton.icon(
            onPressed: aoLimparSelecao,
            icon: const Icon(Icons.close_rounded, size: 16, color: TemasCores.erroVivo),
            label: const Text('Entrada Manual',
                style: TextStyle(color: TemasCores.erroVivo, fontSize: 12)),
          ),
      ],
    );
  }
}

/// Aviso de que a ordem em preenchimento veio de um pedido da App.
class _FaixaPedidoVinculado extends StatelessWidget {
  const _FaixaPedidoVinculado({required this.pedidoId, required this.observacoes});

  final int pedidoId;
  final String? observacoes;

  @override
  Widget build(BuildContext context) {
    final nota = (observacoes != null && observacoes!.isNotEmpty) ? ' • Nota: $observacoes' : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemasCores.avisoFundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.avisoBorda),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: TemasCores.avisoTextoForte, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vinculado ao Pedido #$pedidoId da App$nota',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.avisoTextoForte),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoCliente extends StatelessWidget {
  const _CampoCliente({
    required this.clientes,
    required this.selecionado,
    required this.aoMudar,
  });

  final List<ClienteModel> clientes;
  final String? selecionado;
  final ValueChanged<String?> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Rotulo('Seleção de Cliente'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selecionado,
          decoration: _decoracaoCampo(hintText: 'Selecione um cliente'),
          items: clientes
              .map((c) => DropdownMenuItem<String>(
                    value: c.id.toString(),
                    child: Text(c.nomeCliente),
                  ))
              .toList(),
          onChanged: aoMudar,
          validator: (val) => val == null ? 'Selecione um cliente' : null,
        ),
      ],
    );
  }
}

class _CampoTipoProduto extends StatelessWidget {
  const _CampoTipoProduto({
    required this.tiposProduto,
    required this.selecionado,
    required this.aoMudar,
  });

  final List<Map<String, dynamic>> tiposProduto;
  final String? selecionado;
  final ValueChanged<String?> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Rotulo('Tipo de Produto'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selecionado,
          decoration: _decoracaoCampo(hintText: 'Selecione o tipo de produto'),
          items: tiposProduto
              .map((p) => DropdownMenuItem<String>(
                    value: p['id'].toString(),
                    child: Text(p['nome_tipo_produto'] ?? ''),
                  ))
              .toList(),
          onChanged: aoMudar,
          validator: (val) => val == null ? 'Selecione um tipo de produto' : null,
        ),
      ],
    );
  }
}

class _CamposPrazoEQuantidade extends StatelessWidget {
  const _CamposPrazoEQuantidade({
    required this.dataEntregaController,
    required this.quantidadeController,
    required this.aoEscolherData,
  });

  final TextEditingController dataEntregaController;
  final TextEditingController quantidadeController;
  final VoidCallback aoEscolherData;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Rotulo('Data Prevista de Entrega'),
              const SizedBox(height: 8),
              TextFormField(
                controller: dataEntregaController,
                readOnly: true,
                onTap: aoEscolherData,
                decoration: _decoracaoCampo(
                  hintText: 'aaaa-mm-dd',
                  suffixIcon: const Icon(Icons.calendar_month_outlined,
                      color: TemasCores.textoSecundario),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Indique o prazo' : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Rotulo('Quantidade'),
              const SizedBox(height: 8),
              TextFormField(
                controller: quantidadeController,
                keyboardType: TextInputType.number,
                decoration: _decoracaoCampo(
                  hintText: 'Ex: 100',
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Obrigatório';
                  final qtd = int.tryParse(val);
                  if (qtd == null || qtd <= 0) return 'Inválido';
                  return null;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CampoPrioridade extends StatelessWidget {
  const _CampoPrioridade({required this.selecionada, required this.aoMudar});

  final String selecionada;
  final ValueChanged<String> aoMudar;

  /// Ícone e cor de cada nível de prioridade.
  static ({IconData icone, Color cor}) _estilo(String prio) {
    return switch (prio) {
      'Urgente' => (icone: Icons.warning_amber_rounded, cor: TemasCores.alertaTexto),
      'Crítica' => (icone: Icons.local_fire_department_rounded, cor: TemasCores.erroTextoForte),
      _ => (icone: Icons.circle_outlined, cor: TemasCores.textoApoioForte),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Rotulo('Prioridade da Ordem'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selecionada,
          decoration: _decoracaoCampo(),
          items: niveisPrioridade.map((prio) {
            final estilo = _estilo(prio);
            return DropdownMenuItem<String>(
              value: prio,
              child: Row(
                children: [
                  Icon(estilo.icone, size: 16, color: estilo.cor),
                  const SizedBox(width: 8),
                  Text(
                    prio,
                    style: TextStyle(
                      fontWeight: prio != 'Normal' ? FontWeight.bold : FontWeight.normal,
                      color: estilo.cor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) aoMudar(val);
          },
        ),
      ],
    );
  }
}

class _CampoRequisitosQualidade extends StatelessWidget {
  const _CampoRequisitosQualidade({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Rotulo('Instruções Técnicas & Requisitos de Qualidade (SOP / FAI)'),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: 2,
          decoration: _decoracaoCampo(
            hintText: 'Ex: Tolerância crítica na furação; Validação da 1ª peça (FAI); Cor RAL 3020.',
            padding: const EdgeInsets.all(14),
          ),
        ),
      ],
    );
  }
}

class _BotaoLancar extends StatelessWidget {
  const _BotaoLancar({
    required this.isSaving,
    required this.vinculadoAPedido,
    required this.aoLancar,
  });

  final bool isSaving;
  final bool vinculadoAPedido;
  final VoidCallback aoLancar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isSaving ? null : aoLancar,
        style: ElevatedButton.styleFrom(
          backgroundColor: TemasCores.adminAcento,
          foregroundColor: TemasCores.textoInverso,
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        icon: isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    color: TemasCores.textoInverso, strokeWidth: 2))
            : const Icon(Icons.rocket_launch_outlined, size: 18),
        label: Text(
          vinculadoAPedido ? 'Lançar Pedido da App para Produção' : 'Lançar Encomenda Manual',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
        ),
      ),
    );
  }
}
