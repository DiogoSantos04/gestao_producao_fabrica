import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/cliente_model.dart';
import '../../models/encomenda_model.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/relatorios_repository.dart';
import '../../services/pdf_service.dart';
import '../../widgets/estado_erro.dart';
import 'widgets/mouse_drag_scroll_behavior.dart';

class RelatoriosAdminScreen extends StatefulWidget {
  const RelatoriosAdminScreen({super.key});

  @override
  State<RelatoriosAdminScreen> createState() => _RelatoriosAdminScreenState();
}

class _RelatoriosAdminScreenState extends State<RelatoriosAdminScreen> {
  final _relatoriosRepo = RelatoriosRepository();
  final _encomendasRepo = EncomendasRepository();
  final _clientesRepo = ClientesRepository();
  final _fluxosRepo = FluxosRepository();
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

  List<ClienteModel> _clientesLista = [];
  List<Map<String, dynamic>> _tiposProdutoLista = [];
  /// As avaliações já carregadas — a lista da direita é paginada por scroll.
  List<Map<String, dynamic>> _feedbacks = [];
  bool _aCarregarMaisFeedbacks = false;
  bool _temMaisFeedbacks = false;

  /// Motivo da última falha a apurar os indicadores, ou `null` se correu bem.
  /// Um relatório com zeros por falha de leitura é pior do que um relatório que
  /// não abre: parece um resultado.
  String? _erroCarregamento;

  /// Falha a acrescentar a página seguinte de avaliações.
  String? _erroPaginacaoFeedbacks;

  List<EncomendaModel> _encomendasGeral = [];
  List<Map<String, dynamic>> _dadosHistorico = [];
  List<Map<String, dynamic>> _historicoRelatorios = []; // Guarda os relatórios gerados da BD
  Map<int, int> _ultimaFasePorProduto = {};

  @override
  void initState() {
    super.initState();
    _carregarDadosReais();
    _feedbackScrollController.addListener(_aoDeslizarFeedbacks);
  }

  void _aoDeslizarFeedbacks() {
    if (!_feedbackScrollController.hasClients) return;
    // Depois de uma falha, a retoma é do utilizador — pelo botão de repetir.
    if (_erroPaginacaoFeedbacks != null) return;
    final posicao = _feedbackScrollController.position;
    if (posicao.pixels >= posicao.maxScrollExtent - 200) {
      _carregarMaisFeedbacks();
    }
  }

  /// Acrescenta a página seguinte de avaliações ao fim da lista.
  ///
  /// A avaliação média não é recalculada: já veio do servidor sobre a tabela
  /// inteira e não depende do que está carregado.
  Future<void> _carregarMaisFeedbacks() async {
    if (_aCarregarMaisFeedbacks || !_temMaisFeedbacks) return;
    setState(() {
      _aCarregarMaisFeedbacks = true;
      _erroPaginacaoFeedbacks = null;
    });
    try {
      final pagina = await _relatoriosRepo.obterAvaliacoes(deslocamento: _feedbacks.length);
      if (!mounted) return;
      setState(() {
        _feedbacks = [..._feedbacks, ...pagina.itens];
        _temMaisFeedbacks = pagina.temMais;
        _aCarregarMaisFeedbacks = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar mais avaliações: $e');
      if (mounted) {
        setState(() {
          _aCarregarMaisFeedbacks = false;
          _erroPaginacaoFeedbacks = descreverErro(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _dataInicioController.dispose();
    _dataFimController.dispose();
    _feedbackScrollController.dispose();
    super.dispose();
  }

  // --- DEFINIÇÃO ÚNICA DE "ORDEM CONCLUÍDA" ---

  /// Devolve a data real de conclusão da encomenda, ou `null` se ainda estiver em curso.
  ///
  /// Uma ordem só está concluída quando percorreu todo o roteiro, ou seja quando
  /// `fase_atual_id` é nulo. Estar *na* última fase significa que ela ainda está
  /// a ser executada — contá-la como concluída (e usar `DateTime.now()` como data)
  /// inflacionava o total e falseava a taxa de entrega no prazo.
  DateTime? _obterDataConclusao(
    EncomendaModel enc,
    List<Map<String, dynamic>> historico,
    Map<int, int> ultimaFasePorProduto,
  ) {
    if (enc.faseAtualId != null) return null;

    final int idEnc = enc.id;
    final int? idUltimaFase = ultimaFasePorProduto[enc.tipoProdutoId];

    final registos = historico
        .where((h) => h['encomenda_id'] == idEnc && h['data_conclusao'] != null)
        .toList();
    if (registos.isEmpty) return null;

    // Preferimos o registo da última fase do roteiro; senão, o evento mais recente.
    final fim = registos.where((h) => h['fase_concluida_id'] == idUltimaFase).toList();
    final candidatos = fim.isNotEmpty ? fim : registos;

    DateTime? maisRecente;
    for (final h in candidatos) {
      final d = DateTime.tryParse(h['data_conclusao'].toString());
      if (d != null && (maisRecente == null || d.isAfter(maisRecente))) maisRecente = d;
    }
    return maisRecente;
  }

  /// Compara ao dia: entregar no próprio dia do prazo conta como estando no prazo.
  /// A regra vive em [EncomendaModel.cumpriuPrazo], onde é testável.
  bool _cumpriuPrazo(DateTime? prometida, DateTime dataConclusao) =>
      EncomendaModel.cumpriuPrazo(prometida, dataConclusao);

  // --- PROCESSAMENTO DE DADOS REAIS DA BD ---

  Future<void> _carregarDadosReais() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      // 1. Carregar lista de Clientes para o Dropdown
      final dadosClientes = await _clientesRepo.obterParaSelecao();

      // 2. Carregar lista de Tipos de Produto para o Dropdown
      final dadosTiposProduto = await _fluxosRepo.obterTipologiasParaSelecao();

      // 3. Procurar os Feedbacks Reais (primeira página) e a média global
      final paginaAvaliacoes = await _relatoriosRepo.obterAvaliacoes();
      final avaliacaoMedia = await _relatoriosRepo.obterAvaliacaoMedia();

      // 4. Procurar as encomendas trazendo relacionamentos para o PDF e filtros
      //    (as ordens canceladas não contam para indicadores de desempenho)
      final dadosEncomendas = await _encomendasRepo.obterParaRelatorios();

      // 5. Procurar o histórico de produção completo
      final dadosHistorico = await _encomendasRepo.obterHistoricoCompleto();

      // 6. Procurar a tabela de fases para mapear qual é o fim de linha de cada produto
      final dadosFases = await _fluxosRepo.obterFasesParaMapeamento();

      // 7. Procurar o histórico de relatórios emitidos anteriormente (Auditoria)
      final dadosHistoricoRelatorios = await _relatoriosRepo.obterHistoricoEmissoes();

      // --- MAPEAMENTO DAS ÚLTIMAS FASES (fim de linha de cada tipo de produto) ---
      final Map<int, int> ultimaFasePorProduto = {};
      final Map<int, int> ordemDaUltimaFase = {};
      for (var fase in dadosFases) {
        final int? prodId = fase['tipos_produto_id'] as int?;
        if (prodId == null) continue;
        final int faseId = fase['id'] as int;
        final int ordem = (fase['ordem'] as num?)?.toInt() ?? 0;

        if (!ultimaFasePorProduto.containsKey(prodId) || ordem > (ordemDaUltimaFase[prodId] ?? -1)) {
          ultimaFasePorProduto[prodId] = faseId;
          ordemDaUltimaFase[prodId] = ordem;
        }
      }

      // --- CÁLCULOS LOGÍSTICOS GLOBAIS ---
      int concluidas = 0;
      int noPrazo = 0;

      // A avaliação média vem do servidor: somá-la sobre a lista carregada daria
      // a média das avaliações que por acaso estivessem no ecrã.
      _avaliacaoMedia = avaliacaoMedia;

      // Analisar prazos e conclusões reais
      for (var enc in dadosEncomendas) {
        final DateTime? dataConclusaoReal =
            _obterDataConclusao(enc, dadosHistorico, ultimaFasePorProduto);
        if (dataConclusaoReal == null) continue; // ainda em curso

        concluidas++;
        if (_cumpriuPrazo(enc.dataEntrega, dataConclusaoReal)) noPrazo++;
      }

      if (mounted) {
        setState(() {
          _clientesLista = dadosClientes;
          _tiposProdutoLista = dadosTiposProduto;
          _feedbacks = paginaAvaliacoes.itens;
          _temMaisFeedbacks = paginaAvaliacoes.temMais;
          _encomendasGeral = dadosEncomendas;
          _dadosHistorico = dadosHistorico;
          _historicoRelatorios = dadosHistoricoRelatorios;
          _ultimaFasePorProduto = ultimaFasePorProduto;
          _encomendasConcluidas = concluidas;
          _taxaEntregaNoPrazo = concluidas > 0 ? (noPrazo / concluidas) : 0.0;
          _isLoading = false;
          _erroCarregamento = null;
          _erroPaginacaoFeedbacks = null;
        });
      }
    } catch (e) {
      debugPrint('Erro crítico ao calcular indicadores: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _erroCarregamento = descreverErro(e);
        });
      }
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
      final String utilizadorAuditoria = _relatoriosRepo.utilizadorAtualEmail ?? 'Administrador';
      final DateTime momentoEmissao = DateTime.now();
      final String dataEmissaoStr = "${momentoEmissao.day.toString().padLeft(2, '0')}/${momentoEmissao.month.toString().padLeft(2, '0')}/${momentoEmissao.year} às ${momentoEmissao.hour.toString().padLeft(2, '0')}:${momentoEmissao.minute.toString().padLeft(2, '0')}";

      String nomeClienteFiltro = 'Todos';
      if (_clienteSelecionadoId != null) {
        final clienteFiltrado = _clientesLista.where((c) => c.id == _clienteSelecionadoId);
        if (clienteFiltrado.isNotEmpty) {
          nomeClienteFiltro = clienteFiltrado.first.nomeCliente;
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

      for (final enc in _encomendasGeral) {
        // 1. Filtro de Cliente
        if (_clienteSelecionadoId != null && enc.clienteId != _clienteSelecionadoId) {
          continue;
        }

        // 2. Filtro de Tipo de Produto
        if (_tipoProdutoSelecionadoId != null && enc.tipoProdutoId != _tipoProdutoSelecionadoId) {
          continue;
        }

        final DateTime? dataConclusaoReal =
            _obterDataConclusao(enc, _dadosHistorico, _ultimaFasePorProduto);
        if (dataConclusaoReal == null) continue; // ainda em curso

        // 3. Filtro por Intervalo de Datas
        if (dataConclusaoReal.isAfter(dataInicioFiltro) && dataConclusaoReal.isBefore(dataFimFiltro)) {
          concluidasNoPeriodo++;

          final bool dentroDoPrazo = _cumpriuPrazo(enc.dataEntrega, dataConclusaoReal);
          if (dentroDoPrazo) {
            noPrazoNoPeriodo++;
          }

          linhasTabelaPDF.add([
            enc.codigoRastreio ?? 'TRC-${enc.id}',
            enc.nomeCliente ?? 'N/A',
            enc.nomeProduto ?? 'N/A',
            "${dataConclusaoReal.day.toString().padLeft(2, '0')}/${dataConclusaoReal.month.toString().padLeft(2, '0')}/${dataConclusaoReal.year}",
            dentroDoPrazo ? 'No Prazo' : 'Com Atraso'
          ]);
        }
      }

      final double taxaNoPeriodo = concluidasNoPeriodo > 0 ? (noPrazoNoPeriodo / concluidasNoPeriodo) : 0.0;

      // O desenho do documento vive no PdfService; aqui ficam apenas os dados.
      final bytesPDF = await PdfService.gerarRelatorioProducao(
        ParametrosRelatorioProducao(
          periodoInicio: _dataInicioController.text,
          periodoFim: _dataFimController.text,
          nomeClienteFiltro: nomeClienteFiltro,
          nomeProdutoFiltro: nomeProdutoFiltro,
          utilizadorAuditoria: utilizadorAuditoria,
          dataEmissao: dataEmissaoStr,
          concluidasNoPeriodo: concluidasNoPeriodo,
          taxaNoPeriodo: taxaNoPeriodo,
          avaliacaoMedia: _avaliacaoMedia,
          linhas: linhasTabelaPDF,
        ),
      );

      // --- PERSISTÊNCIA DE AUDITORIA NO SUPABASE ---
      try {
        // 1. Upload do PDF físico e obtenção da URL pública
        final String urlPublica = await _relatoriosRepo.carregarPdf(bytesPDF);

        // 2. Registar o Log de Auditoria na Tabela Relacional
        await _relatoriosRepo.registarEmissao(
          periodoInicio: _dataInicioController.text,
          periodoFim: _dataFimController.text,
          totalConcluidas: concluidasNoPeriodo,
          taxaPrazo: double.parse((taxaNoPeriodo * 100).toStringAsFixed(2)),
          urlPdf: urlPublica,
          geradoPor: utilizadorAuditoria,
        );

        // Recarregar os relatórios para atualizar a interface com o novo log
        await _carregarDadosReais();
      } catch (cloudError) {
        debugPrint('Aviso de Auditoria Cloud: $cloudError');
        if (mounted) {
          context.mostrarSnack(
            'Aviso: PDF gerado, mas o registo de auditoria falhou na nuvem: $cloudError',
            cor: TemasCores.alertaMedio,
            duracao: const Duration(seconds: 4),
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
        context.mostrarSnack(
          'Erro estrutural ao renderizar PDF: $e',
          cor: TemasCores.erroVivo,
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
            colorScheme: const ColorScheme.light(primary: TemasCores.adminAcento, onPrimary: TemasCores.textoInverso, onSurface: TemasCores.textoPrimario),
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

    // Todos os números deste ecrã saem do mesmo carregamento. Se ele falhou, não
    // há relatório nenhum a mostrar — mostrar zeros seria apresentá-los como
    // resultado do período escolhido.
    if (_erroCarregamento != null) {
      return Scaffold(
        backgroundColor: TemasCores.fundoEcraFrio,
        body: EstadoErro(
          titulo: 'Não foi possível calcular os indicadores',
          detalhe: _erroCarregamento,
          aoRepetir: _carregarDadosReais,
        ),
      );
    }

    return ScrollConfiguration(
      behavior: MouseDragScrollBehavior(),
      child: Scaffold(
        backgroundColor: TemasCores.fundoEcraFrio,
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
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: TemasCores.borda)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gerar Relatório', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
              const SizedBox(height: 4),
              const Text('Selecione o período e os filtros para análise', style: TextStyle(fontSize: 12, color: TemasCores.textoTerciario)),
              const SizedBox(height: 24),

              const Text('Data de Início', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataInicioController,
                readOnly: true,
                onTap: () => _selecionarData(context, _dataInicioController),
                decoration: InputDecoration(
                  hintText: 'dd / mm / aaaa',
                  fillColor: TemasCores.superficieSuave,
                  filled: true,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: TemasCores.textoSecundario, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),

              const Text('Data de Fim', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataFimController,
                readOnly: true,
                onTap: () => _selecionarData(context, _dataFimController),
                decoration: InputDecoration(
                  hintText: 'dd / mm / aaaa',
                  fillColor: TemasCores.superficieSuave,
                  filled: true,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: TemasCores.textoSecundario, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 16),

              // --- FILTRO DE SEGMENTAÇÃO: CLIENTE ---
              const Text('Filtrar por Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _clienteSelecionadoId,
                decoration: InputDecoration(
                  fillColor: TemasCores.superficieSuave,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Todos os Clientes', style: TextStyle(fontSize: 13)),
                  ),
                  ..._clientesLista.map((c) {
                    return DropdownMenuItem<int?>(
                      value: c.id,
                      child: Text(c.nomeCliente, style: const TextStyle(fontSize: 13)),
                    );
                  }),
                ],
                onChanged: (val) => setState(() => _clienteSelecionadoId = val),
              ),
              const SizedBox(height: 16),

              // --- FILTRO DE SEGMENTAÇÃO: TIPO DE PRODUTO ---
              const Text('Filtrar por Tipo de Produto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int?>(
                initialValue: _tipoProdutoSelecionadoId,
                decoration: InputDecoration(
                  fillColor: TemasCores.superficieSuave,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                    backgroundColor: TemasCores.adminAcento,
                    foregroundColor: TemasCores.textoInverso,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: _isExporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: TemasCores.textoInverso, strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Gerar Relatório (PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),

              const Text('Estatísticas Rápidas Globais', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
              const SizedBox(height: 20),

              _buildRowIndicador('Encomendas Concluídas', '$_encomendasConcluidas'),
              const SizedBox(height: 6),
              Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: TemasCores.adminAcento, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 24),

              _buildRowIndicador('Taxa de Entrega no Prazo', '${(_taxaEntregaNoPrazo * 100).toInt()}%'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _taxaEntregaNoPrazo,
                backgroundColor: TemasCores.borda,
                color: TemasCores.adminAcento,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Avaliação Média', style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13, fontWeight: FontWeight.w500)),
                  Row(
                    children: [
                      Text('$_avaliacaoMedia', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: TemasCores.textoPrimario)),
                      const SizedBox(width: 6),
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < _avaliacaoMedia.floor() ? Icons.star : Icons.star_border,
                            color: TemasCores.avaliacaoEstrela,
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
              const Text('Histórico e Logs de Auditoria', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
              const SizedBox(height: 4),
              const Text('Registos imutáveis com autoria das emissões', style: TextStyle(fontSize: 11, color: TemasCores.textoTerciario)),
              const SizedBox(height: 16),

              _historicoRelatorios.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Nenhum relatório emitido guardado.', style: TextStyle(fontSize: 12, color: TemasCores.textoDesativado, fontStyle: FontStyle.italic)),
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
                            color: TemasCores.superficieTenue,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: TemasCores.borda),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('$inicio até $fim', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: TemasCores.textoPrimario)),
                                    const SizedBox(height: 3),
                                    Text('Ordens: $total  |  Prazo: ${taxa.toInt()}%', style: const TextStyle(fontSize: 11, color: TemasCores.textoApoioForte)),
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        const Icon(Icons.person_outline_rounded, size: 12, color: TemasCores.textoTerciario),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '$autor ${dataHoraFormatada.isNotEmpty ? "• $dataHoraFormatada" : ""}',
                                            style: const TextStyle(fontSize: 10, color: TemasCores.textoTerciario, fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded, size: 18, color: TemasCores.adminAcento),
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
        Text(label, style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 13, fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: TemasCores.textoPrimario)),
      ],
    );
  }

  Widget _buildPainelDireitoFeedback({required bool eDesktop}) {
    Widget conteudo;

    if (_feedbacks.isEmpty) {
      conteudo = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('Nenhuma avaliação real submetida por clientes na base de dados.', style: TextStyle(color: TemasCores.textoTerciario, fontSize: 13)),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _feedbackScrollController,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _feedbackScrollController,
          // A última posição é o rodapé de paginação, não uma avaliação.
          itemCount: _feedbacks.length + (_temMaisFeedbacks ? 1 : 0),
          padding: const EdgeInsets.only(right: 12),
          itemBuilder: (context, index) {
            if (index == _feedbacks.length) {
              if (_erroPaginacaoFeedbacks != null && !_aCarregarMaisFeedbacks) {
                return EstadoErro.compacto(
                  titulo: 'Não foi possível carregar mais avaliações.',
                  detalhe: _erroPaginacaoFeedbacks,
                  aoRepetir: _carregarMaisFeedbacks,
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Center(
                  child: _aCarregarMaisFeedbacks
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton.icon(
                          onPressed: _carregarMaisFeedbacks,
                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                          label: const Text('Carregar mais', style: TextStyle(fontSize: 13)),
                        ),
                ),
              );
            }
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
                color: TemasCores.superficie,
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
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(codigo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: TemasCores.textoPrimario)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: TemasCores.superficieSuave, borderRadius: BorderRadius.circular(4)),
                              child: Text(cliente, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: TemasCores.textoApoioForte)),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: List.generate(5, (idx) {
                          return Icon(idx < estrelas ? Icons.star : Icons.star_border, color: TemasCores.avaliacaoEstrela, size: 15);
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(data, style: const TextStyle(fontSize: 11, color: TemasCores.textoDesativado)),
                  const SizedBox(height: 12),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: TemasCores.superficieTenue, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: TemasCores.textoDesativado),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            texto,
                            style: const TextStyle(fontSize: 12, color: TemasCores.textoApoioForte, height: 1.4),
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
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: TemasCores.borda)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Feedback dos Clientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
            const SizedBox(height: 4),
            const Text('Avaliações recebidas após conclusão das encomendas', style: TextStyle(fontSize: 12, color: TemasCores.textoTerciario)),
            const SizedBox(height: 20),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 450, child: conteudo),
          ],
        ),
      ),
    );
  }
}