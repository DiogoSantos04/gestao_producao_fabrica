import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfService {
  /// Gera e abre a janela de download/impressão do relatório de turno real
  static Future<void> descarregarRelatorioTurno({
    required String nomeOperador,
    required String dataTurno,
    required int totalFases,
    required int totalIncidencias,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(32),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start, // 👈 CORRIGIDO: nome correto
              children: [
                // Cabeçalho do Relatório
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, // 👈 CORRIGIDO: nome correto
                  children: [
                    pw.Text(
                      'SISTEMA INDUSTRIAL - RELATÓRIO DE TURNO',
                      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                    ),
                    pw.Text(
                      dataTurno,
                      style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.Divider(thickness: 2, color: PdfColors.blue800),
                pw.SizedBox(height: 24),

                // Dados do Operador
                pw.Text('Resumo Operacional', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.SizedBox(height: 16),
                pw.Text('Operador responsável: $nomeOperador', style: const pw.TextStyle(fontSize: 14)),
                pw.Text('Data de processamento: $dataTurno', style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 32),

                // Tabela de Métricas Reais
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Métrica Analisada', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('Quantidade Real', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Fases de Produção Concluídas')),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$totalFases etapas')),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Incidências / Bloqueios Registados')),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            '$totalIncidencias alertas',
                            style: pw.TextStyle(color: totalIncidencias > 0 ? PdfColors.red800 : PdfColors.black),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.Spacer(),

                // Rodapé de Validação
                pw.Divider(color: PdfColors.grey300),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Relatório gerado automaticamente pelo Sistema Industrial 2026', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                    pw.Text('Página 1 de 1', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // Dispara o download nativo ou janela de gravação do browser/sistema
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Relatorio_Turno_${dataTurno.replaceAll('/', '')}.pdf',
    );
  }
}