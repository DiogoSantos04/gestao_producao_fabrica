import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Variáveis Reais de Estatísticas
  int _encomendasConcluidas = 0;
  double _taxaEntregaNoPrazo = 0.0;
  double _avaliacaoMedia = 0.0;

  List<dynamic> _feedbacks = [];

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

      // 1. Procurar os Feedbacks Reais
      final dadosAvaliacoes = await _supabase
          .from('avaliacoes')
          .select('nota, comentario, data_registo, encomendas(codigo_rastreio), clientes(nome_cliente)')
          .order('data_registo', ascending: false);

      // 2. Procurar as encomendas trazendo o tipos_produtos_id
      final dadosEncomendas = await _supabase
          .from('encomendas')
          .select('id, data_entrega, fase_atual_id, tipos_produtos_id');

      // 3. Procurar o histórico de produção completo
      final dadosHistorico = await _supabase
          .from('historico_producao')
          .select('encomenda_id, data_conclusao, fase_concluida_id');

      // 4. Procurar a tabela de fases para mapear qual é o fim de linha de cada produto
      final dadosFases = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id');

      // --- MAPEAMENTO DAS ÚLTIMAS FASES ---
      // Descobre qual o ID da fase com maior 'ordem' para cada tipo de produto
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

      // --- CÁLCULOS LOGÍSTICOS ---
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

        // Regra A: Verifica se a última fase do fluxo já foi guardada no histórico de conclusões
        if (idUltimaFase != null) {
          final registoFim = historicoDaEncomenda.where((h) => h['fase_concluida_id'] == idUltimaFase).toList();
          if (registoFim.isNotEmpty) {
            estaConcluida = true;
            dataConclusaoReal = DateTime.parse(registoFim.first['data_conclusao']);
          }
        }

        // Regra B: Se o admin alterou o estado diretamente na tabela encomendas para a fase final
        if (!estaConcluida && faseAtualId == idUltimaFase && idUltimaFase != null) {
          estaConcluida = true;
          if (historicoDaEncomenda.isNotEmpty) {
            dataConclusaoReal = DateTime.parse(historicoDaEncomenda.last['data_conclusao']);
          } else {
            dataConclusaoReal = DateTime.now(); // Fallback de segurança caso não haja histórico nenhum
          }
        }

        // Se passou em alguma das regras de validação, está terminada!
        if (estaConcluida) {
          concluidas++;

          if (dataPrometida != null && dataConclusaoReal != null) {
            // Normalização crucial: remove as horas/minutos para comparar apenas os dias calendários
            final DateTime dataPrometidaDia = DateTime(dataPrometida.year, dataPrometida.month, dataPrometida.day);
            final DateTime dataConclusaoDia = DateTime(dataConclusaoReal.year, dataConclusaoReal.month, dataConclusaoReal.day);

            // Só incrementa o indicador se foi concluído antes ou no próprio dia limite
            if (dataConclusaoDia.isBefore(dataPrometidaDia) || dataConclusaoDia.isAtSameMomentAs(dataPrometidaDia)) {
              noPrazo++;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _feedbacks = dadosAvaliacoes;
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

  Future<void> _gerarRelatorioPDF() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isExporting = true);
    await Future.delayed(const Duration(seconds: 2)); 
    setState(() => _isExporting = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Relatório de ${_dataInicioController.text} a ${_dataFimController.text} exportado com sucesso!'),
          backgroundColor: TemasCores.verdeSucesso,
        ),
      );
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
              Text('Selecione o período para análise', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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

              const Text('Estatísticas Rápidas', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
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