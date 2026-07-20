import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/temas_cores.dart';

class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class RelatoriosAdminScreen extends StatefulWidget {
  const RelatoriosAdminScreen({super.key});

  @override
  State<RelatoriosAdminScreen> createState() => _RelatoriosAdminScreenState();
}

class _RelatoriosAdminScreenState extends State<RelatoriosAdminScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _dataInicioController = TextEditingController();
  final _dataFimController = TextEditingController();
  final ScrollController _feedbackScrollController = ScrollController();

  bool _isLoading = true;
  bool _isExporting = false;

  // Variáveis Reais de Estatísticas Gerais (Globais)
  int _encomendasConcluidas = 0;
  double _taxaEntregaNoPrazo = 0.0;
  double _avaliacaoMedia = 0.0;

  // Variáveis dos Filtros Avançados
  int? _clienteSelecionadoId;
  int? _tipoProdutoSelecionadoId;

  List<dynamic> _clientesLista = [];
  List<dynamic> _tiposProdutoLista = [];
  List<dynamic> _feedbacks = [];
  List<dynamic> _encomendasGeral = [];
  List<dynamic> _dadosHistorico = [];
  List<dynamic> _historicoRelatorios = []; // Guarda os relatórios gerados da BD
  Map<int, int> _ultimaFasePorProduto = {};

  @override
  void initState() {
    super.initState();
    _carregarDadosReais();
  }

  @override
  void dispose() {
    _dataInicioController.dispose();
    _dataFimController.dispose();
    _feedbackScrollController.dispose();
    super.dispose();
  }

  // --- PROCESSAMENTO DE DADOS REAIS DA BD ---

  Future<void> _carregarDadosReais() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // 1. Carregar lista de Clientes para o Dropdown
      final dadosClientes = await _supabase
          .from('clientes')
          .select('id, nome_cliente')
          .order('nome_cliente');

      // 2. Carregar lista de Tipos de Produto para o Dropdown
      final dadosTiposProduto = await _supabase
          .from('tipos_produto')
          .select('id, nome_tipo_produto')
          .order('nome_tipo_produto');

      // 3. Procurar os Feedbacks Reais
      final dadosAvaliacoes = await _supabase
          .from('avaliacoes')
          .select('nota, comentario, data_registo, encomendas(codigo_rastreio), clientes(nome_cliente)')
          .order('data_registo', ascending: false);

      // 4. Procurar as encomendas trazendo relacionamentos para o PDF e filtros
      final dadosEncomendas = await _supabase
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega, fase_atual_id, cliente_id, tipos_produtos_id, clientes(nome_cliente), tipos_produto:tipos_produtos_id(nome_tipo_produto)');

      // 5. Procurar o histórico de produção completo
      final dadosHistorico = await _supabase
          .from('historico_producao')
          .select('encomenda_id, data_conclusao, fase_concluida_id');

      // 6. Procurar a tabela de fases para mapear qual é o fim de linha de cada produto
      final dadosFases = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id');

      // 7. Procurar o histórico de relatórios emitidos anteriormente (Auditoria)
      final dadosHistoricoRelatorios = await _supabase
          .from('historico_relatorios')
          .select('*')
          .order('data_geracao', ascending: false);

      // --- MAPEAMENTO DAS ÚLTIMAS FASES ---
      Map<int, int> ultimaFasePorProduto = {};
      for (var fase in dadosFases) {
        int prodId = fase['types_produto_id'] ?? fase['tipos_produto_id'];
        int faseId = fase['id'];
        int ordem = fase['ordem'];

        if (!ultimaFasePorProduto.containsKey(prodId)) {
          ultimaFasePorProduto[prodId] = faseId;
        } else {
          var faseExistente = dadosFases.firstWhere((f) => f['id'] == ultimaFasePorProduto[prodId]);
          if (ordem > faseExistente['ordem']) {
            ultimaFasePorProduto[prodId] = faseId;
          }
        }
      }

      // --- CÁLCULOS LOGÍSTICOS GLOBAIS ---
      int concluidas = 0;
      int noPrazo = 0;
      double somaNotas = 0.0;

      // Calcular Avaliação Média Real
      if (dadosAvaliacoes.isNotEmpty) {
        for (var av in dadosAvaliacoes) {
          somaNotas += (av['nota'] ?? 0 as num).toDouble();
        }
        _avaliacaoMedia = double.parse((somaNotas / dadosAvaliacoes.length).toStringAsFixed(1));
      } else {
        _avaliacaoMedia = 0.0;
      }

      // Analisar prazos e conclusões reais
      for (var enc in dadosEncomendas) {
        final int idEnc = enc['id'];
        final int? prodId = enc['tipos_produtos_id'];
        final int? faseAtualId = enc['fase_atual_id'];
        final DateTime? dataPrometida = enc['data_entrega'] != null ? DateTime.parse(enc['data_entrega']) : null;

        final int? idUltimaFase = ultimaFasePorProduto[prodId];
        final historicoDaEncomenda = dadosHistorico.where((h) => h['encomenda_id'] == idEnc).toList();

        bool estaConcluida = false;
        DateTime? dataConclusaoReal;

        if (idUltimaFase != null) {
          final registoFim = historicoDaEncomenda.where((h) => h['fase_concluida_id'] == idUltimaFase).toList();
          if (registoFim.isNotEmpty) {
            estaConcluida = true;
            dataConclusaoReal = DateTime.parse(registoFim.first['data_conclusao']);
          }
        }

        if (!estaConcluida && faseAtualId == idUltimaFase && idUltimaFase != null) {
          estaConcluida = true;
          if (historicoDaEncomenda.isNotEmpty) {
            dataConclusaoReal = DateTime.parse(historicoDaEncomenda.last['data_conclusao']);
          } else {
            dataConclusaoReal = DateTime.now();
          }
        }

        if (estaConcluida) {
          concluidas++;

          if (dataPrometida != null && dataConclusaoReal != null) {
            final DateTime dataPrometidaDia = DateTime(dataPrometida.year, dataPrometida.month, dataPrometida.day);
            final DateTime dataConclusaoDia = DateTime(dataConclusaoReal.year, dataConclusaoReal.month, dataConclusaoReal.day);

            if (dataConclusaoDia.isBefore(dataPrometidaDia) || dataConclusaoDia.isAtSameMomentAs(dataPrometidaDia)) {
              noPrazo++;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _clientesLista = dadosClientes;
          _tiposProdutoLista = dadosTiposProduto;
          _feedbacks = dadosAvaliacoes;
          _encomendasGeral = dadosEncomendas;
          _dadosHistorico = dadosHistorico;
          _historicoRelatorios = dadosHistoricoRelatorios;
          _ultimaFasePorProduto = ultimaFasePorProduto;
          _encomendasConcluidas = concluidas;
          _taxaEntregaNoPrazo = concluidas > 0 ? (noPrazo / concluidas) : 0.0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro crítico ao calcular indicadores: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- GERAÇÃO DO DOCUMENTO PDF REAL E UPLOAD EMPRESARIAL ---

  Future<void> _gerarRelatorioPDF() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isExporting = true);

    try {
      final DateTime dataInicioFiltro = DateTime.parse(_dataInicioController.text);
      final DateTime dataFimFiltro = DateTime.parse(_dataFimController.text).add(const Duration(days: 1));

      // Capturar dados do utilizador para auditoria
      final currentUser = _supabase.auth.currentUser;
      final String utilizadorAuditoria = currentUser?.email ?? 'Administrador';
      final DateTime momentoEmissao = DateTime.now();
      final String dataEmissaoStr = "${momentoEmissao.day.toString().padLeft(2, '0')}/${momentoEmissao.month.toString().padLeft(2, '0')}/${momentoEmissao.year} às ${momentoEmissao.hour.toString().padLeft(2, '0')}:${momentoEmissao.minute.toString().padLeft(2, '0')}";

      // RESOLVIDO: Filtro de segurança contra conflitos de tipo em tempo de execução
      String nomeClienteFiltro = 'Todos';
      if (_clienteSelecionadoId != null) {
        final clienteFiltrado = _clientesLista.where((c) => c['id'] == _clienteSelecionadoId);
        if (clienteFiltrado.isNotEmpty) {
          nomeClienteFiltro = clienteFiltrado.first['nome_cliente'] ?? 'Todos';
        }
      }

      String nomeProdutoFiltro = 'Todos';
      if (_tipoProdutoSelecionadoId != null) {
        final produtoFiltrado = _tiposProdutoLista.where((p) => p['id'] == _tipoProdutoSelecionadoId);
        if (produtoFiltrado.isNotEmpty) {
          nomeProdutoFiltro = produtoFiltrado.first['nome_tipo_produto'] ?? 'Todos';
        }
      }

      int concluidasNoPeriodo = 0;
      int noPrazoNoPeriodo = 0;
      List<List<String>> linhasTabelaPDF = [];

      for (var enc in _encomendasGeral) {
        final int idEnc = enc['id'];
        final int? encClienteId = enc['cliente_id'];
        final int? prodId = enc['tipos_produtos_id'];
        final DateTime? dataPrometida = enc['data_entrega'] != null ? DateTime.parse(enc['data_entrega']) : null;
        final int? idUltimaFase = _ultimaFasePorProduto[prodId];

        // 1. Filtro de Cliente
        if (_clienteSelecionadoId != null && encClienteId != _clienteSelecionadoId) {
          continue;
        }

        // 2. Filtro de Tipo de Produto
        if (_tipoProdutoSelecionadoId != null && prodId != _tipoProdutoSelecionadoId) {
          continue;
        }

        final historicoDaEncomenda = _dadosHistorico.where((h) => h['encomenda_id'] == idEnc).toList();
        DateTime? dataConclusaoReal;
        bool estaConcluida = false;

        if (idUltimaFase != null) {
          final registoFim = historicoDaEncomenda.where((h) => h['fase_concluida_id'] == idUltimaFase).toList();
          if (registoFim.isNotEmpty) {
            estaConcluida = true;
            dataConclusaoReal = DateTime.parse(registoFim.first['data_conclusao']);
          }
        }

        // 3. Filtro por Intervalo de Datas
        if (estaConcluida && dataConclusaoReal != null) {
          if (dataConclusaoReal.isAfter(dataInicioFiltro) && dataConclusaoReal.isBefore(dataFimFiltro)) {
            concluidasNoPeriodo++;

            bool dentroDoPrazo = false;
            if (dataPrometida != null) {
              final DateTime dataPrometidaDia = DateTime(dataPrometida.year, dataPrometida.month, dataPrometida.day);
              final DateTime dataConclusaoDia = DateTime(dataConclusaoReal.year, dataConclusaoReal.month, dataConclusaoReal.day);
              dentroDoPrazo = dataConclusaoDia.isBefore(dataPrometidaDia) || dataConclusaoDia.isAtSameMomentAs(dataPrometidaDia);
            }

            if (dentroDoPrazo) {
              noPrazoNoPeriodo++;
            }

            linhasTabelaPDF.add([
              enc['codigo_rastreio'] ?? 'TRC-$idEnc',
              enc['clientes']?['nome_cliente'] ?? 'N/A',
              enc['tipos_produto']?['nome_tipo_produto'] ?? 'N/A',
              "${dataConclusaoReal.day}/${dataConclusaoReal.month}/${dataConclusaoReal.year}",
              dentroDoPrazo ? 'No Prazo' : 'Com Atraso'
            ]);
          }
        }
      }

      final double taxaNoPeriodo = concluidasNoPeriodo > 0 ? (noPrazoNoPeriodo / concluidasNoPeriodo) : 0.0;

      // Desenhar a estrutura do PDF com Carimbo de Auditoria e Segmentação
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.only(top: 10),
              decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
              child: pw.Text(
                'Documento Auditado - Gerado por: $utilizadorAuditoria em $dataEmissaoStr',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            );
          },
          build: (pw.Context context) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('SISTEMA INDUSTRIAL', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
                pw.Text('Relatorio de Producao', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 10),
            
            // Secção de Parâmetros de Filtro
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Periodo: ${_dataInicioController.text} ate ${_dataFimController.text}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('Emitido por: $utilizadorAuditoria', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text('Filtros Aplicados: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                pw.Text('Cliente: $nomeClienteFiltro  |  Produto: $nomeProdutoFiltro', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
              ],
            ),
            pw.SizedBox(height: 20),

            pw.Text('Indicadores de Desempenho do Periodo', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
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
                  pw.Column(children: [
                    pw.Text('Ordens Concluidas', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text('$concluidasNoPeriodo', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ]),
                  pw.Column(children: [
                    pw.Text('Taxa de Entrega no Prazo', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text('${(taxaNoPeriodo * 100).toInt()}%', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: taxaNoPeriodo >= 0.8 ? PdfColors.green700 : PdfColors.red700)),
                  ]),
                  pw.Column(children: [
                    pw.Text('Satisfacao Media Geral', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    pw.SizedBox(height: 4),
                    pw.Text('$_avaliacaoMedia / 5.0', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            pw.Text('Listagem Analitica de Ordens Finalizadas', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 8),
            linhasTabelaPDF.isEmpty
                ? pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 16),
                    child: pw.Center(child: pw.Text('Nenhuma ordem de producao corresponde aos filtros selecionados.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600))),
                  )
                : pw.Table.fromTextArray(
                    headers: ['Codigo', 'Cliente', 'Produto', 'Data Conclusao', 'Estado'],
                    data: linhasTabelaPDF,
                    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
                    headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    cellHeight: 24,
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerLeft,
                      3: pw.Alignment.center,
                      4: pw.Alignment.center,
                    },
                  ),
          ],
        ),
      );

      final bytesPDF = await pdf.save();

      // --- PERSISTÊNCIA DE AUDITORIA NO SUPABASE ---
      try {
        final String nomeFicheiro = 'relatorio_${DateTime.now().millisecondsSinceEpoch}.pdf';

        // 1. Upload do PDF físico
        await _supabase.storage.from('relatorios').uploadBinary(
              nomeFicheiro,
              bytesPDF,
              fileOptions: const FileOptions(contentType: 'application/pdf'),
            );

        // 2. Obter URL pública
        final String urlPublica = _supabase.storage.from('relatorios').getPublicUrl(nomeFicheiro);

        // 3. Registar o Log de Auditoria na Tabela Relacional
        await _supabase.from('historico_relatorios').insert({
          'periodo_inicio': _dataInicioController.text,
          'periodo_fim': _dataFimController.text,
          'total_concluidas': concluidasNoPeriodo,
          'taxa_prazo': double.parse((taxaNoPeriodo * 100).toStringAsFixed(2)),
          'url_pdf': urlPublica,
          'gerado_por': utilizadorAuditoria,
        });

        // Recarregar os relatórios para atualizar a interface com o novo log
        await _carregarDadosReais();
      } catch (cloudError) {
        debugPrint('Aviso de Auditoria Cloud: $cloudError');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Aviso: PDF gerado, mas o registo de auditoria falhou na nuvem: $cloudError'),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      // --- ABRIR VISUALIZADOR NATIVO DE IMPRESSÃO ---
      await Printing.layoutPdf(
        onLayout: (format) async => bytesPDF,
        name: 'Relatorio_Fabrica_${_dataInicioController.text}.pdf',
      );
    } catch (e) {
      debugPrint('Erro ao gerar relatório: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro estrutural ao renderizar PDF: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _abrirUrlFicheiro(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('Não foi possível abrir o ficheiro: $url');
    }
  }

  Future<void> _selecionarData(BuildContext context, TextEditingController controller) async {
    final DateTime? escolhida = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Colors.black, onPrimary: Colors.white, onSurface: Colors.black87),
          ),
          child: child!,
        );
      },
    );
    if (escolhida != null) {
      setState(() {
        controller.text = "${escolhida.year}-${escolhida.month.toString().padLeft(2, '0')}-${escolhida.day.toString().padLeft(2, '0')}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ScrollConfiguration(
      behavior: MouseDragScrollBehavior(),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Relatórios', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Expanded(
                child: eDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: SingleChildScrollView(child: _buildPainelEsquerdoEstatisticas())),
                          const SizedBox(width: 24),
                          Expanded(flex: 4, child: _buildPainelDireitoFeedback(eDesktop: true)),
                        ],
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            _buildPainelEsquerdoEstatisticas(),
                            const SizedBox(height: 24),
                            _buildPainelDireitoFeedback(eDesktop: false),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPainelEsquerdoEstatisticas() {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gerar Relatório', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 4),
              Text('Selecione o período e os filtros para análise', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 24),

              const Text('Data de Início', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataInicioController,
                readOnly: true,
                onTap: () => _selecionarData(context, _dataInicioController),
                decoration: InputDecoration(
                  hintText: 'dd / mm / aaaa',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: Colors.black54, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),

              const Text('Data de Fim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataFimController,
                readOnly: true,
                onTap: () => _selecionarData(context, _dataFimController),
                decoration: InputDecoration(
                  hintText: 'dd / mm / aaaa',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: Colors.black54, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),

              // --- FILTRO DE SEGMENTAÇÃO: CLIENTE ---
              const Text('Filtrar por Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: _clienteSelecionadoId,
                decoration: InputDecoration(
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos os Clientes', style: TextStyle(fontSize: 13)),
                  ),
                  ..._clientesLista.map((c) {
                    return DropdownMenuItem<int?>(
                      value: c['id'] as int,
                      child: Text(c['nome_cliente'] ?? '', style: const TextStyle(fontSize: 13)),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _clienteSelecionadoId = val),
              ),
              const SizedBox(height: 16),

              // --- FILTRO DE SEGMENTAÇÃO: TIPO DE PRODUTO ---
              const Text('Filtrar por Tipo de Produto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                value: _tipoProdutoSelecionadoId,
                decoration: InputDecoration(
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos os Tipos de Produto', style: TextStyle(fontSize: 13)),
                  ),
                  ..._tiposProdutoLista.map((p) {
                    return DropdownMenuItem<int?>(
                      value: p['id'] as int,
                      child: Text(p['nome_tipo_produto'] ?? '', style: const TextStyle(fontSize: 13)),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _tipoProdutoSelecionadoId = val),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isExporting ? null : _gerarRelatorioPDF,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111625),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: _isExporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Gerar Relatório (PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),

              const Text('Estatísticas Rápidas Globais', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 20),

              _buildRowIndicador('Encomendas Concluídas', '$_encomendasConcluidas'),
              const SizedBox(height: 6),
              Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF111625), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),

              _buildRowIndicador('Taxa de Entrega no Prazo', '${(_taxaEntregaNoPrazo * 100).toInt()}%'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _taxaEntregaNoPrazo,
                backgroundColor: Colors.grey.shade200,
                color: const Color(0xFF111625),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Avaliação Média', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
                  Row(
                    children: [
                      Text('$_avaliacaoMedia', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                      const SizedBox(width: 6),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < _avaliacaoMedia.floor() ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                            size: 16,
                          );
                        }),
                      )
                    ],
                  ),
                ],
              ),

              // --- MÓDULO DE AUDITORIA E LOGS ---
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),
              const Text('Histórico e Logs de Auditoria', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 4),
              Text('Registos imutáveis com autoria das emissões', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 16),

              _historicoRelatorios.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Nenhum relatório emitido guardado.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                    )
                  : Column(
                      children: List.generate(_historicoRelatorios.length, (idx) {
                        final rel = _historicoRelatorios[idx];
                        final String inicio = rel['periodo_inicio'] ?? '';
                        final String fim = rel['periodo_fim'] ?? '';
                        final int total = rel['total_concluidas'] ?? 0;
                        final double taxa = (rel['taxa_prazo'] as num? ?? 0.0).toDouble();
                        final String url = rel['url_pdf'] ?? '';
                        final String autor = rel['gerado_por'] ?? 'Administrador';

                        final String dataGeracaoRaw = rel['data_geracao'] ?? '';
                        String dataHoraFormatada = '';
                        if (dataGeracaoRaw.isNotEmpty) {
                          try {
                            final dt = DateTime.parse(dataGeracaoRaw).toLocal();
                            dataHoraFormatada = "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                          } catch (_) {
                            dataHoraFormatada = dataGeracaoRaw;
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$inicio até $fim', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                                    const SizedBox(height: 3),
                                    Text('Ordens: $total  |  Prazo: ${taxa.toInt()}%', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        Icon(Icons.person_outline_rounded, size: 12, color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$autor ${dataHoraFormatada.isNotEmpty ? "• $dataHoraFormatada" : ""}',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF111625)),
                                tooltip: 'Abrir PDF impresso',
                                onPressed: () => _abrirUrlFicheiro(url),
                              )
                            ],
                          ),
                        );
                      }),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRowIndicador(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
      ],
    );
  }

  Widget _buildPainelDireitoFeedback({required bool eDesktop}) {
    Widget conteudo;

    if (_feedbacks.isEmpty) {
      conteudo = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('Nenhuma avaliação real submetida por clientes na base de dados.', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _feedbackScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _feedbackScrollController,
          itemCount: _feedbacks.length,
          padding: const EdgeInsets.only(right: 12),
          itemBuilder: (context, index) {
            final fb = _feedbacks[index];
            final String codigo = fb['encomendas']?['codigo_rastreio'] ?? 'TRC-N/A';
            final String cliente = fb['clientes']?['nome_cliente'] ?? 'Cliente Desconhecido';
            final String data = fb['data_registo'] ?? '';
            final int estrelas = fb['nota'] ?? 5;
            final String texto = fb['comentario'] ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(codigo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(cliente, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: List.generate(5, (idx) {
                          return Icon(idx < estrelas ? Icons.star : Icons.star_border, color: Colors.amber, size: 15);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(data, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            texto,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Feedback dos Clientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 4),
            Text('Avaliações recebidas após conclusão das encomendas', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 20),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 450, child: conteudo),
          ],
        ),
      ),
    );
  }
}