import '../models/incidencia_model.dart';
import '../repositories/operador_repository.dart';
import 'pdf_service.dart';

/// Monta os parâmetros do relatório de turno a partir dos registos do operador.
///
/// Vive fora de [PdfService] de propósito: o serviço de PDF desenha, e não
/// conhece os modelos do domínio. Vive fora dos ecrãs porque os dois sítios que
/// geram este relatório — a área de relatórios e o fecho de sessão — têm de
/// produzir exatamente o mesmo documento.
///
/// Tudo é derivado de [registos] e [incidencias]: os totais saem das mesmas
/// listas que preenchem as tabelas, pelo que o resumo no topo do PDF não pode
/// discordar do detalhe em baixo.
///
/// [incidencias] são as que o operador registou no período
/// ([OperadorRepository.obterIncidenciasRegistadas]). O total junta-as às
/// paragens associadas às fases concluídas, sem contar duas vezes a mesma: as
/// incidências antigas, sem autor gravado, só se encontram pela segunda via.
ParametrosRelatorioTurno construirRelatorioTurno({
  required String nomeOperador,
  required DateTime dia,
  required List<RegistoDeTurno> registos,
  List<IncidenciaModel> incidencias = const [],
}) {
  final metricas = MetricasDoDia.apurar(registos);

  final ordenados = [...registos]..sort((a, b) {
      final ma = a.registo.momento;
      final mb = b.registo.momento;
      if (ma == null || mb == null) return 0;
      return ma.compareTo(mb);
    });

  final linhas = ordenados.map((r) {
    final momento = r.registo.momento?.toLocal();
    return [
      momento == null ? '--:--' : horaCurta(momento),
      r.codigoRastreio ?? 'Sem codigo',
      r.nomeProduto ?? 'Sem produto',
      r.registo.nomeFase ?? 'Fase desconhecida',
      r.motivos.isEmpty ? '-' : r.motivos.join('; '),
    ];
  }).toList();

  final idsIncidencias = <int>{
    for (final r in registos)
      for (final p in r.paragens) p.id,
    for (final i in incidencias) i.id,
  };

  final linhasIncidencias = incidencias.map((i) {
    final momento = i.inicio?.toLocal();
    final observacoes = i.descricaoOperador?.trim();
    return [
      momento == null ? '--:--' : horaCurta(momento),
      i.codigoRastreio ?? 'Sem codigo',
      i.nomePosto ?? '-',
      i.rotulo ?? '-',
      (observacoes == null || observacoes.isEmpty) ? '-' : observacoes,
      estadoIncidenciaLegivel(i.estado),
    ];
  }).toList();

  return ParametrosRelatorioTurno(
    nomeOperador: nomeOperador,
    dataTurno: dataCurta(dia),
    totalFases: registos.length,
    totalIncidencias: idsIncidencias.length,
    linhasIncidencias: linhasIncidencias,
    ordensDistintas: metricas.ordensDistintas,
    primeiraConclusao:
        metricas.primeira == null ? null : horaCurta(metricas.primeira!),
    ultimaConclusao:
        metricas.ultima == null ? null : horaCurta(metricas.ultima!),
    intervaloMedio: metricas.intervaloMedio == null
        ? null
        : duracaoLegivel(metricas.intervaloMedio!),
    intervalosIgnorados: metricas.intervalosIgnorados,
    linhas: linhas,
  );
}

/// Estado da incidência em português corrente, para o papel.
String estadoIncidenciaLegivel(String estado) {
  switch (estado.toUpperCase()) {
    case 'PENDENTE':
      return 'Pendente';
    case 'EM_ANALISE':
      return 'Em analise';
    case 'EM_INTERVENCAO':
      return 'Em intervencao';
    case 'AGUARDA_LINE_CLEARANCE':
      return 'Aguarda line clearance';
    case 'RESOLVIDO':
      return 'Resolvida';
    case 'CANCELADO':
      return 'Cancelada';
    default:
      return estado;
  }
}

String _d2(int n) => n.toString().padLeft(2, '0');

/// Data em `dd/mm/aaaa`.
String dataCurta(DateTime d) => '${_d2(d.day)}/${_d2(d.month)}/${d.year}';

/// Hora em `hh:mm`.
String horaCurta(DateTime d) => '${_d2(d.hour)}:${_d2(d.minute)}';

/// Duração em português corrente, sem casas decimais nem segundos supérfluos.
String duracaoLegivel(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  final minutos = d.inMinutes.remainder(60);
  return minutos == 0 ? '${d.inHours} h' : '${d.inHours} h $minutos min';
}
