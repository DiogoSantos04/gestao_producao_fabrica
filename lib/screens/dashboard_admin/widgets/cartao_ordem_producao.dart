import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/formatos.dart';
import '../../../core/temas_cores.dart';
import '../../../models/encomenda_model.dart';
import '../../../models/estado_ordem.dart';
import '../../../widgets/etiqueta_estado.dart';

/// Cartão de uma ordem de produção na lista do painel de controlo.
///
/// Não sabe nada de rede: recebe o progresso já calculado (a percentagem depende
/// do roteiro do produto, que vive no ecrã) e devolve as ações por callback.
class CartaoOrdemProducao extends StatelessWidget {
  const CartaoOrdemProducao({
    super.key,
    required this.encomenda,
    required this.progresso,
    required this.aoAvancarFase,
    required this.aoWipHold,
    required this.aoRegistoTecnico,
    required this.aoLineClearance,
    required this.aoHistorico,
    required this.aoEditar,
    required this.aoCancelar,
  });

  final EncomendaModel encomenda;

  /// Fração entre 0 e 1 do roteiro já percorrido.
  final double progresso;

  final VoidCallback aoAvancarFase;
  final VoidCallback aoWipHold;
  final ValueChanged<Map<String, dynamic>?> aoRegistoTecnico;
  final ValueChanged<Map<String, dynamic>?> aoLineClearance;
  final VoidCallback aoHistorico;
  final VoidCallback aoEditar;

  /// Recebe a referência já formatada, que é o que o diálogo de confirmação mostra.
  final ValueChanged<String> aoCancelar;

  @override
  Widget build(BuildContext context) {
    final enc = encomenda;
    final idFormatado = Formatos.referenciaOrdem(
      enc.id,
      criadaEm: enc.createdAt?.toIso8601String(),
    );
    final String codigoRastreio = enc.codigoRastreio ?? 'N/A';
    final String nomeCliente = enc.nomeCliente ?? 'N/A';
    final String nomeProduto = enc.nomeProduto ?? 'N/A';
    final String prioridade = enc.prioridade;

    final estado = enc.estado;
    final bool cancelada = estado == EstadoOrdem.cancelada;
    final bool emHold = estado == EstadoOrdem.emHold;
    final bool concluida = estado == EstadoOrdem.concluida;

    final String faseNome = concluida
        ? 'Produção Concluída'
        : (enc.nomeFaseAtual != null
              ? 'Fase ${enc.ordemFaseAtual}: ${enc.nomeFaseAtual}'
              : 'Aguardando Início');
    final String postoTrabalho = enc.postoFaseAtual ?? 'Linha Geral';
    final String dataEntrega = enc.dataEntregaIso ?? '';

    final int progressoPercentagem = (progresso * 100).toInt();
    final bool atrasada = _estaAtrasada(enc.dataEntrega);

    // Incidência ativa: o modelo aplica a regra (sem line clearance validado)
    final Map<String, dynamic>? incidenciaAtiva = enc.incidenciaAtiva;
    final bool manutencaoConcluida =
        incidenciaAtiva?['manutencao_concluida'] == true;

    final infoEsquerda = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _LinhaEtiquetas(
          idFormatado: idFormatado,
          codigoRastreio: codigoRastreio,
          estado: estado,
          atrasada: atrasada,
          prioridade: prioridade,
        ),
        const SizedBox(height: 8),
        Text(
          nomeCliente,
          style: const TextStyle(
            color: TemasCores.textoApoioForte,
            fontSize: 13,
          ),
        ),
        Text(
          nomeProduto,
          style: const TextStyle(
            color: TemasCores.textoTerciario,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Fase Atual: ',
              style: TextStyle(fontSize: 13, color: TemasCores.textoApoio),
            ),
            Flexible(
              child: Text(
                faseNome,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: TemasCores.textoPrimario,
                ),
              ),
            ),
            if (!concluida) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text(
                  postoTrabalho,
                  style: const TextStyle(fontSize: 10),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
      ],
    );

    // Até 5 botões cabem nesta zona (WIP Hold, Avançar Fase, Histórico,
    // Editar, Cancelar) — lado a lado com a referência da ordem, um ecrã
    // estreito não tinha onde os pôr: a coluna de botões reclamava a largura
    // toda antes do `Expanded` da esquerda sequer entrar em conta, e a
    // referência ("ORD-2026-109") acabava espremida a uma letra por linha.
    Widget construirDataEAcoes({required bool amplo}) {
      return Column(
        crossAxisAlignment: amplo
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: TemasCores.textoTerciario,
              ),
              const SizedBox(width: 6),
              Text(
                dataEntrega,
                style: const TextStyle(
                  fontSize: 12,
                  color: TemasCores.textoApoio,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _BotoesAcao(
            alinhamento: amplo ? WrapAlignment.end : WrapAlignment.start,
            estado: estado,
            incidenciaAtiva: incidenciaAtiva,
            manutencaoConcluida: manutencaoConcluida,
            aoAvancarFase: aoAvancarFase,
            aoWipHold: aoWipHold,
            aoRegistoTecnico: aoRegistoTecnico,
            aoLineClearance: aoLineClearance,
            aoHistorico: aoHistorico,
            aoEditar: aoEditar,
            aoCancelar: () => aoCancelar(idFormatado),
          ),
          const SizedBox(height: 16),
          Text(
            '$progressoPercentagem% concluído',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: TemasCores.textoApoio,
            ),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: emHold ? TemasCores.erroClaro : TemasCores.borda,
          width: emHold ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: context.ehAmplo
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: infoEsquerda),
                      const SizedBox(width: 16),
                      construirDataEAcoes(amplo: true),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      infoEsquerda,
                      const SizedBox(height: 16),
                      construirDataEAcoes(amplo: false),
                    ],
                  ),
          ),

          // MOTIVO DO CANCELAMENTO (rasto de auditoria)
          if (cancelada) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: TemasCores.superficieSuave,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: TemasCores.bordaForte),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.block_rounded,
                    color: TemasCores.textoApoioForte,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ORDEM CANCELADA em ${Formatos.dataHora(enc.dataCancelamento?.toIso8601String())} — '
                      '${enc.motivoCancelamento ?? 'sem motivo registado'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TemasCores.textoApoioIntenso,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // BANNER ALERTA DE INCIDÊNCIA ATIVA / ESTADO DA REPARAÇÃO
          if (emHold && incidenciaAtiva != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: manutencaoConcluida
                    ? TemasCores.sucessoFundo
                    : TemasCores.avisoFundo,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: manutencaoConcluida
                      ? TemasCores.sucessoClaro
                      : TemasCores.avisoBorda,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    manutencaoConcluida
                        ? Icons.build_circle_rounded
                        : Icons.warning_rounded,
                    color: manutencaoConcluida
                        ? TemasCores.sucessoTextoForte
                        : TemasCores.avisoTextoForte,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manutencaoConcluida
                              ? 'REPARAÇÃO TÉCNICA CONCLUÍDA — AGUARDA LINE CLEARANCE (QUALIDADE)'
                              : 'BLOQUEIO EM LINHA: ${incidenciaAtiva['motivo'] ?? 'Manutenção Pendente'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: manutencaoConcluida
                                ? TemasCores.sucessoTextoIntenso
                                : TemasCores.avisoTextoForte,
                          ),
                        ),
                        if (incidenciaAtiva['descricao_operador'] != null &&
                            incidenciaAtiva['descricao_operador']
                                .toString()
                                .isNotEmpty)
                          Text(
                            'Nota Operador: ${incidenciaAtiva['descricao_operador']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: manutencaoConcluida
                                  ? TemasCores.sucessoTextoForte
                                  : TemasCores.avisoTexto,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: TemasCores.superficieSuave,
              valueColor: AlwaysStoppedAnimation<Color>(
                emHold
                    ? TemasCores.erro
                    : (concluida ? TemasCores.sucesso : TemasCores.marcaEscura),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _estaAtrasada(DateTime? dataEntrega) {
  if (dataEntrega == null) return false;
  final hoje = DateTime.now();
  final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
  return hojeSemHoras.isAfter(dataEntrega);
}

/// Cores do badge de estado, derivadas de [EstadoOrdem].
({Color fundo, Color borda, Color texto}) _coresEstado(EstadoOrdem estado) {
  return switch (estado) {
    EstadoOrdem.cancelada => (
      fundo: TemasCores.superficieInerte,
      borda: TemasCores.bordaNeutra,
      texto: TemasCores.inativoTexto,
    ),
    EstadoOrdem.emHold => (
      fundo: TemasCores.erroFundo,
      borda: TemasCores.erroClaro,
      texto: TemasCores.erroTextoForte,
    ),
    EstadoOrdem.concluida => (
      fundo: TemasCores.sucessoFundo,
      borda: TemasCores.sucessoClaro,
      texto: TemasCores.sucessoTextoForte,
    ),
    EstadoOrdem.emProducao => (
      fundo: TemasCores.infoFundo,
      borda: TemasCores.infoClaro,
      texto: TemasCores.infoTextoForte,
    ),
  };
}

/// Etiqueta simples com fundo colorido.
Widget _etiqueta(
  String rotulo, {
  required Color fundo,
  required Color texto,
  double paddingHorizontal = 8,
}) {
  return EtiquetaEstado.compacta(
    rotulo: rotulo,
    fundo: fundo,
    texto: texto,
    paddingHorizontal: paddingHorizontal,
  );
}

/// Linha de etiquetas do cartão: referência, código de rastreio, estado,
/// atraso e prioridade.
class _LinhaEtiquetas extends StatelessWidget {
  const _LinhaEtiquetas({
    required this.idFormatado,
    required this.codigoRastreio,
    required this.estado,
    required this.atrasada,
    required this.prioridade,
  });

  final String idFormatado;
  final String codigoRastreio;
  final EstadoOrdem estado;
  final bool atrasada;
  final String prioridade;

  @override
  Widget build(BuildContext context) {
    final cores = _coresEstado(estado);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          idFormatado,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: TemasCores.textoPrimario,
          ),
        ),
        _etiqueta(
          codigoRastreio,
          fundo: TemasCores.superficieSuave,
          texto: TemasCores.textoApoioForte,
          paddingHorizontal: 6,
        ),
        EtiquetaEstado.compacta(
          rotulo: estado.etiqueta,
          fundo: cores.fundo,
          texto: cores.texto,
          borda: cores.borda,
        ),
        if (atrasada)
          _etiqueta(
            'Atrasada',
            fundo: TemasCores.erroFundo,
            texto: TemasCores.erroTexto,
          ),
        if (prioridade != 'Normal')
          _etiqueta(
            prioridade.toUpperCase(),
            fundo: TemasCores.alertaFundo,
            texto: TemasCores.alertaTextoForte,
          ),
      ],
    );
  }
}

/// Botões de ação do cartão, condicionados ao estado da ordem.
///
/// Regras preservadas do original: uma ordem **cancelada** só permite consultar
/// o histórico; em **hold** mostra Registo Técnico ou Line Clearance conforme a
/// manutenção já esteja registada; **em produção** mostra WIP Hold e Avançar Fase;
/// **concluída** mostra apenas Histórico, Editar e Cancelar.
class _BotoesAcao extends StatelessWidget {
  const _BotoesAcao({
    required this.alinhamento,
    required this.estado,
    required this.incidenciaAtiva,
    required this.manutencaoConcluida,
    required this.aoAvancarFase,
    required this.aoWipHold,
    required this.aoRegistoTecnico,
    required this.aoLineClearance,
    required this.aoHistorico,
    required this.aoEditar,
    required this.aoCancelar,
  });

  final WrapAlignment alinhamento;
  final EstadoOrdem estado;
  final Map<String, dynamic>? incidenciaAtiva;
  final bool manutencaoConcluida;
  final VoidCallback aoAvancarFase;
  final VoidCallback aoWipHold;
  final ValueChanged<Map<String, dynamic>?> aoRegistoTecnico;
  final ValueChanged<Map<String, dynamic>?> aoLineClearance;
  final VoidCallback aoHistorico;
  final VoidCallback aoEditar;
  final VoidCallback aoCancelar;

  @override
  Widget build(BuildContext context) {
    final cancelada = estado == EstadoOrdem.cancelada;
    final emHold = estado == EstadoOrdem.emHold;
    final concluida = estado == EstadoOrdem.concluida;

    const paddingBotao = EdgeInsets.symmetric(horizontal: 12, vertical: 12);
    final contornoNeutro = OutlinedButton.styleFrom(
      side: const BorderSide(color: TemasCores.bordaForte),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      padding: paddingBotao,
    );

    // `Wrap` em vez de `Row`: até 5 botões (WIP Hold, Avançar Fase,
    // Histórico, Editar, Cancelar) não cabem numa linha só em ecrã estreito —
    // passam para a linha seguinte em vez de forçar o cartão a alargar.
    return Wrap(
      alignment: alinhamento,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!cancelada && emHold) ...[
          if (!manutencaoConcluida)
            ElevatedButton.icon(
              onPressed: () => aoRegistoTecnico(incidenciaAtiva),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.avisoTexto,
                foregroundColor: TemasCores.textoInverso,
                padding: paddingBotao,
              ),
              icon: const Icon(Icons.build_rounded, size: 14),
              label: const Text(
                'Registo Técnico',
                style: TextStyle(fontSize: 12),
              ),
            )
          else ...[
            // Com a manutenção fechada, o registo continua acessível: é o que o
            // administrador tem de ler antes de dar o Line Clearance. Enquanto
            // este botão desaparecia com a conclusão, o relatório do técnico não
            // chegava a ser visto por ninguém.
            OutlinedButton.icon(
              onPressed: () => aoRegistoTecnico(incidenciaAtiva),
              style: contornoNeutro,
              icon: const Icon(Icons.fact_check_outlined, size: 14),
              label: const Text(
                'Ver Registo Técnico',
                style: TextStyle(fontSize: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => aoLineClearance(incidenciaAtiva),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.sucessoTexto,
                foregroundColor: TemasCores.textoInverso,
                padding: paddingBotao,
              ),
              icon: const Icon(Icons.verified_user_rounded, size: 14),
              label: const Text(
                'Line Clearance',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ] else if (!cancelada && !concluida) ...[
          OutlinedButton.icon(
            onPressed: aoWipHold,
            style: OutlinedButton.styleFrom(
              foregroundColor: TemasCores.erroTexto,
              side: const BorderSide(color: TemasCores.erroClaro),
              padding: paddingBotao,
            ),
            icon: const Icon(Icons.pause, size: 14),
            label: const Text('WIP Hold', style: TextStyle(fontSize: 12)),
          ),
          ElevatedButton.icon(
            onPressed: aoAvancarFase,
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.marcaEscura,
              foregroundColor: TemasCores.textoInverso,
              padding: paddingBotao,
            ),
            icon: const Icon(Icons.skip_next_rounded, size: 14),
            label: const Text('Avançar Fase', style: TextStyle(fontSize: 12)),
          ),
        ],

        OutlinedButton.icon(
          onPressed: aoHistorico,
          style: contornoNeutro,
          icon: const Icon(
            Icons.history_rounded,
            size: 14,
            color: TemasCores.acentoAzulAcinzentado,
          ),
          label: const Text(
            'Histórico',
            style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12),
          ),
        ),

        if (!cancelada) ...[
          OutlinedButton.icon(
            onPressed: aoEditar,
            style: contornoNeutro,
            icon: const Icon(
              Icons.edit_outlined,
              size: 14,
              color: TemasCores.textoPrimario,
            ),
            label: const Text(
              'Editar',
              style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12),
            ),
          ),
          OutlinedButton.icon(
            onPressed: aoCancelar,
            style: contornoNeutro,
            icon: const Icon(
              Icons.cancel_outlined,
              size: 14,
              color: TemasCores.textoPrimario,
            ),
            label: const Text(
              'Cancelar',
              style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
