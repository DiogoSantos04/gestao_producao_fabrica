import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

// Classe que força o Flutter a aceitar arrastamento direto com o rato no meio da lista
class MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class CriarEncomendaScreen extends StatefulWidget {
  const CriarEncomendaScreen({super.key});

  @override
  State<CriarEncomendaScreen> createState() => _CriarEncomendaScreenState();
}

class _CriarEncomendaScreenState extends State<CriarEncomendaScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  RealtimeChannel? _planeamentoSubscription;

  // 🕹️ Controladores dedicados para tornar as barras de scroll laterais clicáveis no computador
  final ScrollController _previewScrollController = ScrollController();
  final ScrollController _ultimasScrollController = ScrollController();

  List<dynamic> _clientes = [];
  List<dynamic> _tiposProduto = [];
  List<dynamic> _previewFases = [];
  List<dynamic> _ultimasEncomendas = [];
  
  String? _clienteSelecionado;
  String? _tipoProdutoSelecionado;
  final _dataEntregaController = TextEditingController();
  final _quantidadeController = TextEditingController(text: '1');
  
  bool _isLoadingData = true;
  bool _isLoadingPreview = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _inicializarSubscricaoRealtime();
  }

  @override
  void dispose() {
    _dataEntregaController.dispose();
    _quantidadeController.dispose();
    _previewScrollController.dispose(); // 👈 Limpeza dos controladores em memória
    _ultimasScrollController.dispose();
    if (_planeamentoSubscription != null) {
      _supabase.removeChannel(_planeamentoSubscription!);
    }
    super.dispose();
  }

  // --- BUSCA DE DADOS & REALTIME (SUPABASE) ---

  void _inicializarSubscricaoRealtime() {
    _planeamentoSubscription = _supabase.channel('db-planeamento-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'tipos_produto',
        callback: (payload) {
          debugPrint('⚡ [Realtime] Tipos de produto atualizados detetados!');
          _carregarDados();
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'encomendas',
        callback: (payload) {
          _carregarDados();
        },
      );

    _planeamentoSubscription?.subscribe();
  }

  Future<void> _carregarDados() async {
    try {
      final clientesData = await _supabase.from('clientes').select('id, nome_cliente');
      final produtosData = await _supabase.from('tipos_produto').select('id, nome_tipo_produto').order('nome_tipo_produto');
      
      final encomendasData = await _supabase
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega, quantidade, clientes(nome_cliente), tipos_produto:tipos_produtos_id(nome_tipo_produto)')
          .order('id', ascending: false)
          .limit(15);

      if (mounted) {
        setState(() {
          _clientes = clientesData;
          _tiposProduto = produtosData;
          _ultimasEncomendas = encomendasData;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      _mostrarMensagem('Erro ao carregar dados: $e', eErro: true);
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _carregarPreviewFluxo(String tipoProdutoId) async {
    setState(() {
      _isLoadingPreview = true;
      _previewFases = [];
    });

    try {
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('nome_fase_padrao, ordem, tempo_estimado, posto_trabalho')
          .eq('tipos_produto_id', int.parse(tipoProdutoId))
          .order('ordem');

      if (mounted) {
        setState(() {
          _previewFases = fasesData;
          _isLoadingPreview = false;
        });
        // Faz reset ao scroll para o topo sempre que carrega um produto novo
        if (_previewScrollController.hasClients) {
          _previewScrollController.jumpTo(0);
        }
      }
    } catch (e) {
      _mostrarMensagem('Erro ao gerar pré-visualização: $e', eErro: true);
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  // --- REGRAS DE NEGÓCIO ---

  String _gerarCodigoRastreio() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final sufixo = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    return 'TRC-$sufixo';
  }

  Future<void> _lancarEncomenda() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final int prodId = int.parse(_tipoProdutoSelecionado!);

      final faseInicialData = await _supabase
          .from('fases_padrao')
          .select('id')
          .eq('tipos_produto_id', prodId)
          .eq('ordem', 1)
          .maybeSingle();

      if (faseInicialData == null) {
        throw Exception('Não foi encontrada nenhuma fase inicial (Ordem 1) definida para este tipo de produto.');
      }

      final faseInicialId = faseInicialData['id'];
      final codigoRastreio = _gerarCodigoRastreio();

      await _supabase.from('encomendas').insert({
        'codigo_rastreio': codigoRastreio,
        'data_entrega': _dataEntregaController.text,
        'cliente_id': int.parse(_clienteSelecionado!),
        'tipos_produtos_id': prodId,
        'fase_atual_id': faseInicialId,
        'quantidade': int.parse(_quantidadeController.text),
      });

      _mostrarMensagem('Ordem $codigoRastreio lançada com sucesso!');
      
      setState(() {
        _clienteSelecionado = null;
        _tipoProdutoSelecionado = null;
        _dataEntregaController.clear();
        _quantidadeController.text = '1';
        _previewFases = [];
      });
      _carregarDados();

    } catch (e) {
      _mostrarMensagem('Erro ao lançar encomenda: ${e.toString().replaceAll('Exception: ', '')}', eErro: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataEscolhida = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataEscolhida != null) {
      setState(() {
        _dataEntregaController.text = "${dataEscolhida.year}-${dataEscolhida.month.toString().padLeft(2, '0')}-${dataEscolhida.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _mostrarMensagem(String msg, {bool eErro = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: eErro ? TemasCores.vermelhoErro : TemasCores.verdeSucesso,
        ),
      );
    }
  }

  // --- CONSTRUÇÃO DA UI RESPONSIVA ---

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 950;

    if (_isLoadingData) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return ScrollConfiguration(
      behavior: MouseDragScrollBehavior(),
      child: eDesktop
          ? Scaffold(
              backgroundColor: Colors.grey.shade50,
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Planeamento',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4, 
                            child: SingleChildScrollView(child: _buildPainelEsquerdoForm())
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                Expanded(child: _buildPainelDireitoPreview(eDesktop: true)),
                                const SizedBox(height: 24),
                                Expanded(child: _buildPainelDireitoUltimas(eDesktop: true)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Scaffold(
              backgroundColor: Colors.grey.shade50,
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Planeamento',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    _buildPainelEsquerdoForm(),
                    const SizedBox(height: 24),
                    _buildPainelDireitoPreview(eDesktop: false),
                    const SizedBox(height: 24),
                    _buildPainelDireitoUltimas(eDesktop: false),
                  ],
                ),
              ),
            ),
    );
  }

  // --- COLUNA DA ESQUERDA: FORMULÁRIO ---
  Widget _buildPainelEsquerdoForm() {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lançar Nova Encomenda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                'Preencha os dados para iniciar uma nova ordem de produção',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 32),

              const Text('Seleção de Cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _clienteSelecionado,
                decoration: InputDecoration(
                  hintText: 'Selecione um cliente',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                items: _clientes.map((c) {
                  return DropdownMenuItem<String>(
                    value: c['id'].toString(),
                    child: Text(c['nome_cliente'] ?? ''),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _clienteSelecionado = val),
                validator: (val) => val == null ? 'Selecione um cliente' : null,
              ),
              const SizedBox(height: 20),

              const Text('Tipo de Produto', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _tipoProdutoSelecionado,
                decoration: InputDecoration(
                  hintText: 'Selecione o tipo de produto',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                items: _tiposProduto.map((p) {
                  return DropdownMenuItem<String>(
                    value: p['id'].toString(),
                    child: Text(p['nome_tipo_produto'] ?? ''),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _tipoProdutoSelecionado = val);
                  if (val != null) _carregarPreviewFluxo(val);
                },
                validator: (val) => val == null ? 'Selecione um tipo de produto' : null,
              ),
              const SizedBox(height: 20),

              const Text('Data Prevista de Entrega', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dataEntregaController,
                readOnly: true,
                onTap: () => _selecionarData(context),
                decoration: InputDecoration(
                  hintText: 'dd / mm / aaaa',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  suffixIcon: const Icon(Icons.calendar_month_outlined, color: Colors.black54),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Indique o prazo de entrega' : null,
              ),
              const SizedBox(height: 20),

              const Text('Quantidade', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _quantidadeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Ex: 100',
                  fillColor: Colors.grey.shade100,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Indique a quantidade';
                  if (int.tryParse(val) == null || int.parse(val) <= 0) return 'Indique um número válido superior a 0';
                  return null;
                },
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _lancarEncomenda,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111625),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text(
                          'Lançar Encomenda',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- COLUNA DA DIREITA (CIMA): PRÉ-VISUALIZAÇÃO ---
  Widget _buildPainelDireitoPreview({required bool eDesktop}) {
    Widget conteudo;

    if (_isLoadingPreview) {
      conteudo = const Center(child: CircularProgressIndicator());
    } else if (_previewFases.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Selecione um tipo de produto para ver o fluxo',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _previewScrollController, // 🥇 Vinculado ao controlador da Scrollbar
        thumbVisibility: true,
        child: ListView.builder(
          controller: _previewScrollController, // 🥇 Vinculado exatamente ao mesmo controlador da ListView
          itemCount: _previewFases.length,
          padding: const EdgeInsets.only(right: 16),
          itemBuilder: (context, idx) {
            final f = _previewFases[idx];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      '${f['ordem']}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f['nome_fase_padrao'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        if (f['posto_trabalho'] != null && f['posto_trabalho'].toString().isNotEmpty)
                          Text(
                            'Posto: ${f['posto_trabalho']}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '⏱️ ${f['tempo_estimado']} min',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pré-visualização do Fluxo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              'Fases que a encomenda irá seguir automaticamente',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 320, child: conteudo),
          ],
        ),
      ),
    );
  }

  // --- COLUNA DA DIREITA (BAIXO): ÚLTIMAS ENCOMENDAS ---
  Widget _buildPainelDireitoUltimas({required bool eDesktop}) {
    Widget conteudo;

    if (_ultimasEncomendas.isEmpty) {
      conteudo = const Center(
        child: Text(
          'Nenhuma encomenda registada recentemente.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    } else {
      conteudo = Scrollbar(
        controller: _ultimasScrollController, // 🥈 Vinculado ao controlador da Scrollbar
        thumbVisibility: true,
        child: ListView.builder(
          controller: _ultimasScrollController, // 🥈 Vinculado exatamente ao mesmo controlador da ListView
          itemCount: _ultimasEncomendas.length,
          padding: const EdgeInsets.only(right: 16),
          itemBuilder: (context, index) {
            final enc = _ultimasEncomendas[index];
            final idFormated = 'ORD-2026-${enc['id'].toString().padLeft(3, '0')}';
            
            final nomeCliente = enc['clientes'] != null ? enc['clientes']['nome_cliente'] : 'Desconhecido';
            final nomeProduto = enc['tipos_produto'] != null ? enc['tipos_produto']['nome_tipo_produto'] : 'N/A';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              idFormated,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                enc['codigo_rastreio'] ?? '',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(nomeCliente, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                        Text(nomeProduto, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        enc['data_entrega'] ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          'Qtd: ${enc['quantidade'] ?? 1}',
                          style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Últimas Encomendas Lançadas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            eDesktop ? Expanded(child: conteudo) : SizedBox(height: 400, child: conteudo),
          ],
        ),
      ),
    );
  }
}