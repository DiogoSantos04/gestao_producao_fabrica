import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RelatoriosOperadorScreen extends StatefulWidget {
  const RelatoriosOperadorScreen({super.key});

  @override
  State<RelatoriosOperadorScreen> createState() => _RelatoriosOperadorScreenState();
}

class _RelatoriosOperadorScreenState extends State<RelatoriosOperadorScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  DateTime? _dataInicio;
  DateTime? _dataFim;
  bool _isGenerating = false;

  // Lista de relatórios fictícios que simula o histórico de PDFs gerados pelo operador (Figura 34)
  final List<Map<String, String>> _relatoriosRecentes = [
    {
      'nome': 'Relatorio_Turno_20012026.pdf',
      'data': '20/01/2026 18:30',
    },
    {
      'nome': 'Relatorio_Producao_19012026.pdf',
      'data': '19/01/2026 18:25',
    },
    {
      'nome': 'Relatorio_Turno_18012026.pdf',
      'data': '18/01/2026 18:35',
    },
  ];

  // Controlador para abrir o calendário nativo do Flutter
  Future<void> _selecionarData(BuildContext context, bool isInicio) async {
    final DateTime? selecionada = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6), // Azul do mockup
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (selecionada != null) {
      setState(() {
        if (isInicio) {
          _dataInicio = selecionada;
        } else {
          _dataFim = selecionada;
        }
      });
    }
  }

  String _formatarDataVisual(DateTime? data) {
    if (data == null) return 'dd/mm/aaaa';
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  // Simulação e processamento da exportação de dados com base nas datas selecionadas
  Future<void> _gerarEExportarPDF() async {
    if (_dataInicio == null || _dataFim == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione ambas as datas.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_dataInicio!.isAfter(_dataFim!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data de início não pode ser posterior à data de fim.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Consulta de verificação para saber quantos registos existem no intervalo
      final logsData = await _supabase
          .from('historico_producao')
          .select('id')
          .eq('utilizador_id', user.id)
          .gte('data_conclusao', _dataInicio!.toIso8601String())
          .lte('data_conclusao', _dataFim!.add(const Duration(days: 1)).toIso8601String());

      final totalRegistos = (logsData as List).length;

      // Pequeno delay para simular a compilação e renderização do PDF
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        // Mostra feedback de sucesso ao utilizador
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 28),
                SizedBox(width: 8),
                Text('PDF Exportado'),
              ],
            ),
            content: Text(
              'O relatório foi gerado com sucesso!\n\n'
              '• Intervalo: ${_formatarDataVisual(_dataInicio)} a ${_formatarDataVisual(_dataFim)}\n'
              '• Total de fases concluídas no período: $totalRegistos\n\n'
              'O download começará automaticamente no seu navegador.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        );

        // Adiciona dinamicamente o novo PDF à lista de recentes
        setState(() {
          final novaDataStr = '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
          _relatoriosRecentes.insert(0, {
            'nome': 'Relatorio_Producao_${_dataInicio!.day}${_dataInicio!.month}_${_dataFim!.day}${_dataFim!.month}.pdf',
            'data': novaDataStr,
          });
          _isGenerating = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao gerar relatório: $e');
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho - Figura 34
              const Text(
                'Área de Relatórios',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gere e consulte relatórios de produção',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 32),

              // Bloco de Configuração do Relatório (Card Superior - Figura 34)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Relatório de Produção',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Seletores de data lado a lado
                        Row(
                          children: [
                            // Data de Início
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Data de Início',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () => _selecionarData(context, true),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatarDataVisual(_dataInicio),
                                            style: TextStyle(
                                              color: _dataInicio == null ? Colors.grey.shade400 : const Color(0xFF1E293B),
                                              fontSize: 14,
                                            ),
                                          ),
                                          Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade400),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Data de Fim
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Data de Fim',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  InkWell(
                                    onTap: () => _selecionarData(context, false),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatarDataVisual(_dataFim),
                                            style: TextStyle(
                                              color: _dataFim == null ? Colors.grey.shade400 : const Color(0xFF1E293B),
                                              fontSize: 14,
                                            ),
                                          ),
                                          Icon(Icons.calendar_today_outlined, size: 18, color: Colors.grey.shade400),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Botão Exportar PDF
                        ElevatedButton.icon(
                          onPressed: _isGenerating ? null : _gerarEExportarPDF,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6), // Azul do mockup
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: _isGenerating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.download, size: 18),
                          label: const Text(
                            'Exportar PDF',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Bloco de Relatórios Recentes (Lista Inferior - Figura 34)
              const Text(
                'Relatórios Recentes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                color: Colors.white,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _relatoriosRecentes.length,
                  separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (context, index) {
                    final item = _relatoriosRecentes[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.picture_as_pdf_outlined, color: Colors.red.shade400, size: 24),
                      ),
                      title: Text(
                        item['nome']!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          item['data']!,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.download_outlined, color: Color(0xFF64748B)),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('A descarregar ${item['nome']}...')),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}