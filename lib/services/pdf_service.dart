import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Parâmetros de um relatório de produção.
///
/// Agrupa os valores que antes eram variáveis locais dentro do método de 226
/// linhas do ecrã de relatórios.
class ParametrosRelatorioProducao {
  final String periodoInicio;
  final String periodoFim;
  final String nomeClienteFiltro;
  final String nomeProdutoFiltro;
  final String utilizadorAuditoria;
  final String dataEmissao;
  final int concluidasNoPeriodo;
  final double taxaNoPeriodo;
  final double avaliacaoMedia;

  /// Linhas da tabela analítica: código, cliente, produto, data, estado.
  final List<List<String>> linhas;

  const ParametrosRelatorioProducao({
    required this.periodoInicio,
    required this.periodoFim,
    required this.nomeClienteFiltro,
    required this.nomeProdutoFiltro,
    required this.utilizadorAuditoria,
    required this.dataEmissao,
    required this.concluidasNoPeriodo,
    required this.taxaNoPeriodo,
    required this.avaliacaoMedia,
    required this.linhas,
  });
}

/// Parâmetros do relatório de turno de um operador.
///
/// Recebe texto já formatado, e não modelos do domínio: o serviço de PDF não
/// conhece repositórios, pela mesma razão que [ParametrosRelatorioProducao]
/// recebe as linhas prontas.
class ParametrosRelatorioTurno {
  final String nomeOperador;
  final String dataTurno;
  final int totalFases;
  final int totalIncidencias;
  final int ordensDistintas;

  /// Horas da primeira e da última conclusão do dia, ou `null` sem atividade.
  final String? primeiraConclusao;
  final String? ultimaConclusao;

  /// Intervalo médio entre conclusões, já legível. `null` quando não houve
  /// intervalos mensuráveis (uma só fase no dia, ou só pausas).
  final String? intervaloMedio;

  /// Intervalos descartados por serem pausas — declarados no rodapé da tabela.
  final int intervalosIgnorados;

  /// Uma linha por fase concluída: hora, código, produto, fase, paragem.
  final List<List<String>> linhas;

  /// Uma linha por incidência registada pelo operador no período: hora,
  /// código, posto, motivo, observações, estado.
  final List<List<String>> linhasIncidencias;

  const ParametrosRelatorioTurno({
    required this.nomeOperador,
    required this.dataTurno,
    required this.totalFases,
    required this.totalIncidencias,
    required this.ordensDistintas,
    required this.linhas,
    this.linhasIncidencias = const [],
    this.primeiraConclusao,
    this.ultimaConclusao,
    this.intervaloMedio,
    this.intervalosIgnorados = 0,
  });
}

class PdfService {
  /// Desenha o relatório de produção e devolve os bytes do PDF.
  ///
  /// O desenho vivia dentro de `_gerarRelatorioPDF` no ecrã, misturado com o
  /// cálculo dos KPIs, o upload e o registo de auditoria.
  static Future<Uint8List> gerarRelatorioProducao(ParametrosRelatorioProducao p) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => _rodapeAuditoria(p),
        build: (context) => [
          _cabecalho(),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          pw.SizedBox(height: 10),
          _parametrosFiltro(p),
          pw.SizedBox(height: 20),
          _indicadores(p),
          pw.SizedBox(height: 24),
          _listagemAnalitica(p),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _rodapeAuditoria(ParametrosRelatorioProducao p) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Text(
        'Documento Auditado - Gerado por: ${p.utilizadorAuditoria} em ${p.dataEmissao}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    );
  }

  static pw.Widget _cabecalho() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('SISTEMA INDUSTRIAL',
            style: const pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
        pw.Text('Relatorio de Producao',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
      ],
    );
  }

  static pw.Widget _parametrosFiltro(ParametrosRelatorioProducao p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Periodo: ${p.periodoInicio} ate ${p.periodoFim}',
                style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text('Emitido por: ${p.utilizadorAuditoria}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text('Filtros Aplicados: ',
                style: const pw.TextStyle(
                    fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.Text('Cliente: ${p.nomeClienteFiltro}  |  Produto: ${p.nomeProdutoFiltro}',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _indicadores(ParametrosRelatorioProducao p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Indicadores de Desempenho do Periodo',
            style: const pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            color: PdfColors.grey100,
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _indicador('Ordens Concluidas', '${p.concluidasNoPeriodo}'),
              _indicador(
                'Taxa de Entrega no Prazo',
                '${(p.taxaNoPeriodo * 100).toInt()}%',
                cor: p.taxaNoPeriodo >= 0.8 ? PdfColors.green700 : PdfColors.red700,
              ),
              _indicador('Satisfacao Media Geral', '${p.avaliacaoMedia} / 5.0'),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _indicador(String titulo, String valor, {PdfColor? cor}) {
    return pw.Column(children: [
      pw.Text(titulo, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.Text(valor,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: cor)),
    ]);
  }

  static pw.Widget _listagemAnalitica(ParametrosRelatorioProducao p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Listagem Analitica de Ordens Finalizadas',
            style: const pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
        pw.SizedBox(height: 8),
        if (p.linhas.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 16),
            child: pw.Center(
              child: pw.Text('Nenhuma ordem de producao corresponde aos filtros selecionados.',
                  style: const pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600)),
            ),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Codigo', 'Cliente', 'Produto', 'Data Conclusao', 'Estado'],
            data: p.linhas,
            headerStyle:
                const pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellHeight: 24,
            cellAlignments: const {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.center,
            },
          ),
      ],
    );
  }

  /// 1. Gera e abre a janela de download/impressão do relatório de turno real
  static Future<void> descarregarRelatorioTurno(
    ParametrosRelatorioTurno p,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        footer: (context) => _rodapeTurno(context),
        build: (context) => [
          _cabecalhoTurno(p),
          pw.SizedBox(height: 24),
          _identificacaoTurno(p),
          pw.SizedBox(height: 20),
          _indicadoresTurno(p),
          pw.SizedBox(height: 24),
          _detalheTurno(p),
          pw.SizedBox(height: 24),
          _incidenciasTurno(p),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Relatorio_Turno_${p.dataTurno.replaceAll('/', '')}.pdf',
    );
  }

  static pw.Widget _cabecalhoTurno(ParametrosRelatorioTurno p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'SISTEMA INDUSTRIAL - RELATÓRIO DE TURNO',
              style: const pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
            ),
            pw.Text(
              p.dataTurno,
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Divider(thickness: 2, color: PdfColors.blue800),
      ],
    );
  }

  static pw.Widget _identificacaoTurno(ParametrosRelatorioTurno p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Resumo Operacional',
            style: const pw.TextStyle(
                fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
        pw.SizedBox(height: 12),
        pw.Text('Operador responsável: ${p.nomeOperador}',
            style: const pw.TextStyle(fontSize: 14)),
        pw.Text('Data de processamento: ${p.dataTurno}',
            style: const pw.TextStyle(fontSize: 14)),
        if (p.primeiraConclusao != null && p.ultimaConclusao != null)
          pw.Text(
            'Atividade registada entre as ${p.primeiraConclusao} e as ${p.ultimaConclusao}',
            style: const pw.TextStyle(fontSize: 14),
          ),
      ],
    );
  }

  static pw.Widget _indicadoresTurno(ParametrosRelatorioTurno p) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _celulaTurno('Métrica Analisada', negrito: true),
            _celulaTurno('Valor Apurado', negrito: true),
          ],
        ),
        pw.TableRow(children: [
          _celulaTurno('Fases de Produção Concluídas'),
          _celulaTurno('${p.totalFases} etapas'),
        ]),
        pw.TableRow(children: [
          _celulaTurno('Incidências / Bloqueios Registados'),
          _celulaTurno(
            '${p.totalIncidencias} alertas',
            cor: p.totalIncidencias > 0 ? PdfColors.red800 : PdfColors.black,
          ),
        ]),
        pw.TableRow(children: [
          _celulaTurno('Ordens de Fabrico Distintas'),
          _celulaTurno('${p.ordensDistintas} ordens'),
        ]),
        pw.TableRow(children: [
          _celulaTurno('Intervalo Médio entre Conclusões'),
          _celulaTurno(p.intervaloMedio ?? 'Sem intervalos medíveis'),
        ]),
      ],
    );
  }

  static pw.Widget _celulaTurno(String texto, {bool negrito = false, PdfColor? cor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        texto,
        style: pw.TextStyle(
          fontWeight: negrito ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: cor,
        ),
      ),
    );
  }

  static pw.Widget _detalheTurno(ParametrosRelatorioTurno p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Detalhe das Fases Concluídas',
            style: const pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
        pw.SizedBox(height: 8),
        if (p.linhas.isEmpty)
          pw.Text('Sem fases concluídas neste dia.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Hora', 'Codigo', 'Produto', 'Fase', 'Paragem'],
            data: p.linhas,
            headerStyle: const pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.1),
              1: pw.FlexColumnWidth(1.8),
              2: pw.FlexColumnWidth(2.2),
              3: pw.FlexColumnWidth(2.2),
              4: pw.FlexColumnWidth(2.7),
            },
          ),
        // A média de intervalos exclui as pausas; dizê-lo aqui é o que a torna
        // auditável por quem recebe o papel.
        if (p.intervalosIgnorados > 0)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'Nota: ${p.intervalosIgnorados} intervalo(s) superior(es) a 2 horas foram '
              'considerados pausas e excluídos do intervalo médio.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
      ],
    );
  }

  /// Incidências registadas pelo operador no turno, independentemente de a
  /// fase já ter sido concluída — uma ordem em WIP Hold não fecha a fase, e era
  /// por isso que a incidência desaparecia do relatório.
  static pw.Widget _incidenciasTurno(ParametrosRelatorioTurno p) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Incidências Registadas no Turno',
            style: const pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
        pw.SizedBox(height: 8),
        if (p.linhasIncidencias.isEmpty)
          pw.Text('Sem incidências registadas neste turno.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
        else
          pw.TableHelper.fromTextArray(
            headers: const ['Hora', 'Codigo', 'Posto', 'Motivo', 'Observacoes', 'Estado'],
            data: p.linhasIncidencias,
            headerStyle: const pw.TextStyle(
                fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellHeight: 22,
            columnWidths: const {
              0: pw.FlexColumnWidth(1.0),
              1: pw.FlexColumnWidth(1.6),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(2.6),
              4: pw.FlexColumnWidth(2.6),
              5: pw.FlexColumnWidth(1.6),
            },
          ),
      ],
    );
  }

  static pw.Widget _rodapeTurno(pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      padding: const pw.EdgeInsets.only(top: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Relatório gerado automaticamente pelo Sistema Industrial 2026',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  /// 2. Gera e descarrega o Certificado de Conformidade e Passaporte do Produto para o Cliente
  static Future<void> descarregarCertificadoConformidade({
    required String codigoRastreio,
    required String nomeCliente,
    required String nomeProduto,
    required int quantidade,
    required String dataEntrega,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Cabeçalho Oficial
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'CERTIFICADO DE CONFORMIDADE',
                          style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple900),
                        ),
                        pw.Text(
                          'Garantia de Qualidade & Passaporte do Produto',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.deepPurple),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'ISO 9001:OK',
                        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.deepPurple),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Divider(thickness: 1.5, color: PdfColors.deepPurple),
                pw.SizedBox(height: 20),

                // Declaração Oficial
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'A nossa unidade fabril certifica que o lote e produto abaixo descriminados foram fabricados, inspecionados e testados de acordo com as especificações técnicas aplicáveis e normas de controlo de qualidade.',
                    style: const pw.TextStyle(fontSize: 11, lineSpacing: 1.4),
                  ),
                ),
                pw.SizedBox(height: 24),

                // Tabela com Detalhes do Produto
                pw.Text('Dados da Encomenda:', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  headers: ['Campo', 'Especificação'],
                  data: [
                    ['Código de Rastreio / Lote', codigoRastreio],
                    ['Cliente Destinatário', nomeCliente],
                    ['Artigo Produzido', nomeProduto],
                    ['Quantidade Aprovada', '$quantidade unidade(s)'],
                    ['Data de Conclusão', dataEntrega],
                    ['Estado de Controlo', 'APROVADO (100% Conforme)'],
                  ],
                  headerStyle: const pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.deepPurple),
                  rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
                  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                pw.Spacer(),

                // Bloco de Assinatura Digital / Carimbo
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Carimbo do Controlo de Qualidade:', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                        pw.SizedBox(height: 6),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.green)),
                          child: pw.Text(
                            ' INSPEÇÃO TÉCNICA OK ',
                            style: const pw.TextStyle(color: PdfColors.green900, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(width: 150, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 4),
                        pw.Text('Responsável de Qualidade', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Sistema MES Automatizado 2026', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Certificado_$codigoRastreio.pdf',
    );
  }
}