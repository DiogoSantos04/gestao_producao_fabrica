import 'package:flutter/material.dart';

import '../../../core/formatos.dart';
import '../../../core/temas_cores.dart';
import '../../../models/encomenda_model.dart';
import '../../../models/historico_model.dart';
import '../../../models/incidencia_model.dart';
import '../../../repositories/encomendas_repository.dart';

/// Timeline de rastreabilidade de uma ordem: fases concluídas e paragens.
///
/// Só lê — não devolve nada a quem a abre.
class DialogoHistoricoOrdem extends StatelessWidget {
  final EncomendaModel encomenda;
  final EncomendasRepository repositorio;

  const DialogoHistoricoOrdem({
    super.key,
    required this.encomenda,
    required this.repositorio,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required EncomendaModel encomenda,
    required EncomendasRepository repositorio,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DialogoHistoricoOrdem(
        encomenda: encomenda,
        repositorio: repositorio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final idFormatado = Formatos.referenciaOrdem(
      encomenda.id,
      criadaEm: encomenda.createdAt?.toIso8601String(),
    );

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history_edu_rounded, color: TemasCores.marcaEscura),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Histórico & Rastreabilidade - $idFormatado',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 550,
        height: 450,
        child: FutureBuilder(
          future: repositorio.obterTimeline(encomenda.id),
          builder: (context, AsyncSnapshot<TimelineOrdem> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Erro ao carregar histórico: ${snapshot.error}',
                  style: const TextStyle(color: TemasCores.erro),
                ),
              );
            }

            final eventos = construirEventosTimeline(snapshot.data);

            if (eventos.isEmpty) {
              return const Center(
                child: Text(
                  'Nenhum evento registado no histórico desta ordem.',
                  style: TextStyle(color: TemasCores.textoTerciario),
                ),
              );
            }

            eventos.sort((a, b) =>
                (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

            return ListView.builder(
              itemCount: eventos.length,
              itemBuilder: (context, idx) => _EventoTimeline(
                evento: eventos[idx],
                ultimo: idx == eventos.length - 1,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

/// Uma linha da timeline: o marcador ligado ao seguinte e o cartão do evento.
class _EventoTimeline extends StatelessWidget {
  final Map<String, dynamic> evento;
  final bool ultimo;

  const _EventoTimeline({required this.evento, required this.ultimo});

  @override
  Widget build(BuildContext context) {
    final cor = evento['cor'] as Color;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: cor.withOpacity(0.15),
                child: Icon(evento['icone'] as IconData, size: 16, color: cor),
              ),
              if (!ultimo)
                Container(width: 2, height: 35, color: TemasCores.bordaForte),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TemasCores.superficieTenue,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: TemasCores.borda),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          evento['titulo'].toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: cor,
                          ),
                        ),
                      ),
                      Text(
                        Formatos.dataHora(evento['data_str']),
                        style: const TextStyle(
                          fontSize: 10,
                          color: TemasCores.textoTerciario,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    evento['subtitulo'].toString(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: TemasCores.textoApoioIntenso,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Converte a rastreabilidade da ordem numa lista de eventos.
///
/// Cada incidência pode gerar até três eventos: o WIP Hold, a reparação técnica
/// e o line clearance. A ordenação (do mais recente para o mais antigo) fica a
/// cargo de quem apresenta.
List<Map<String, dynamic>> construirEventosTimeline(TimelineOrdem? timeline) {
  final eventos = <Map<String, dynamic>>[];

  for (final p in timeline?.producao ?? const <HistoricoModel>[]) {
    final data = p.momento;
    eventos.add({
      'timestamp': data ?? DateTime.now(),
      'data_str': data?.toIso8601String() ?? '',
      'titulo':
          'Concluída Fase ${p.ordemFase ?? ''}: ${p.nomeFase ?? 'Fase de Produção'}',
      'subtitulo': 'Executado por: ${p.nomeUtilizador ?? 'Operador'}',
      'tipo': 'PRODUCAO',
      'cor': TemasCores.sucessoTexto,
      'icone': Icons.check_circle_rounded,
    });
  }

  for (final inc in timeline?.incidencias ?? const <IncidenciaModel>[]) {
    final dataRegisto = inc.inicio;
    final motivo = inc.motivo ?? 'Incidente em Linha';
    final notaOp = inc.descricaoOperador;

    eventos.add({
      'timestamp': dataRegisto ?? DateTime.now(),
      'data_str': dataRegisto?.toIso8601String() ?? '',
      'titulo': 'WIP Hold (Linha Suspensa)',
      'subtitulo':
          'Motivo: $motivo${notaOp != null && notaOp.isNotEmpty ? "\nNota: $notaOp" : ""}',
      'tipo': 'HOLD',
      'cor': TemasCores.erroTexto,
      'icone': Icons.pause_circle_filled_rounded,
    });

    if (inc.manutencaoConcluida) {
      final dataManut = inc.dataFimManutencao ?? dataRegisto;
      final notaTec = inc.notaTecnica ?? '';
      eventos.add({
        'timestamp': dataManut ?? DateTime.now(),
        'data_str': dataManut?.toIso8601String() ?? '',
        'titulo':
            'Reparação Técnica Concluída (${inc.tipoManutencao ?? 'N/A'})',
        'subtitulo':
            'Responsável: ${inc.responsavelIntervencao ?? 'Técnico'}${notaTec.isNotEmpty ? "\nRelatório: $notaTec" : ""}',
        'tipo': 'MANUTENCAO',
        'cor': TemasCores.avisoTextoForte,
        'icone': Icons.build_circle_rounded,
      });
    }

    if (inc.lineClearanceValidado && inc.dataLineClearance != null) {
      final dataClearance = inc.dataLineClearance!;
      eventos.add({
        'timestamp': dataClearance,
        'data_str': dataClearance.toIso8601String(),
        'titulo': 'Line Clearance Aprovado (Produção Retomada)',
        'subtitulo': 'Aprovado por Responsável de Qualidade/Supervisão',
        'tipo': 'CLEARANCE',
        'cor': TemasCores.infoTextoForte,
        'icone': Icons.verified_user_rounded,
      });
    }
  }

  return eventos;
}
