import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({super.key});

  @override
  State<PainelControloScreen> createState() => _PainelControloScreenState();
}

class _PainelControloScreenState extends State<PainelControloScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<dynamic> _encomendas = [];
  List<dynamic> _encomendasFiltradas = [];
  Map<int, List<dynamic>> _fasesPorProduto = {}; // Mapeia tipos_produto_id -> lista de fases padrão
  bool _isLoading = true;
  
  // Variável para guardar o canal de escuta em tempo real
  RealtimeChannel? _encomendasSubscription;

  @override
  void initState() {
    super.initState();
    // Carrega os dados iniciais e, logo de seguida, ativa o Realtime
    _carregarDados(mostrarLoader: true).then((_) => _ativarSubscricaoRealtime());
    _searchController.addListener(_filtrarEncomendas);
  }

  @override
  void dispose() {
    // É crucial fechar o canal quando mudamos de ecrã para evitar fugas de memória
    if (_encomendasSubscription != null) {
      _supabase.removeChannel(_encomendasSubscription!);
    }
    _searchController.dispose();
    super.dispose();
  }

  // --- CONSULTAS À BASE DE DADOS (SUPABASE) ---

  // Adicionado o parâmetro mostrarLoader para podermos atualizar os dados em background de forma fluida
  Future<void> _carregarDados({bool mostrarLoader = false}) async {
    try {
      if (mostrarLoader) setState(() => _isLoading = true);

      // 1. Carrega todas as fases padrão ordenadas para sabermos o total de fases de cada produto
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id')
          .order('ordem');

      final Map<int, List<dynamic>> tempFasesPorProduto = {};
      for (var f in fasesData) {
        final prodId = f['types_produto_id'] ?? f['tipos_produto_id'] as int;
        tempFasesPorProduto.putIfAbsent(prodId, () => []).add(f);
      }

      // 2. Carrega apenas as encomendas EM CURSO com JOINs estruturados
      final encomendasData = await _supabase
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega, quantidade, cliente_id, tipos_produtos_id, fase_atual_id, clientes(nome_cliente), tipos_produto:tipos_produtos_id(nome_tipo_produto), fase_atual:fase_atual_id(nome_fase_padrao, ordem)')
          .not('fase_atual_id', 'is', null)
          .order('id', ascending: false);

      if (mounted) {
        setState(() {
          _fasesPorProduto = tempFasesPorProduto;
          _encomendas = encomendasData;
          _isLoading = false;
        });
        _filtrarEncomendas();
      }
    } catch (e) {
      _mostrarMensagem('Erro ao carregar ordens: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ativa a escuta de eventos em tempo real na tabela encomendas
  void _ativarSubscricaoRealtime() {
    _encomendasSubscription = _supabase
        .channel('public:encomendas_painel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // Ouve INSERTS, UPDATES e DELETES
          schema: 'public',
          table: 'encomendas',
          callback: (payload) {
            debugPrint('Alteração detetada na produção! A atualizar dados...');
            // Recarrega os dados em background (silenciosamente) sem disparar o ecrã de carregamento inteiro
            _carregarDados(mostrarLoader: false);
          },
        )
        .subscribe();
  }

  void _filtrarEncomendas() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _encomendasFiltradas = _encomendas.where((e) {
        final codigo = (e['codigo_rastreio'] ?? '').toString().toLowerCase();
        final cliente = (e['clientes'] != null ? e['clientes']['nome_cliente'] : '').toString().toLowerCase();
        return codigo.contains(query) || cliente.contains(query);
      }).toList();
    });
  }

  // --- OPERAÇÕES E REGRAS DE NEGÓCIO ---

  /// Calcula a percentagem de progresso da encomenda refletindo o trabalho JÁ CONCLUÍDO
  double _calcularProgresso(Map<String, dynamic> enc) {
    final int? prodId = enc['tipos_produtos_id'] as int?;
    final faseAtual = enc['fase_atual'];

    if (prodId == null || faseAtual == null) return 0.0;

    final fases = _fasesPorProduto[prodId];
    if (fases == null || fases.isEmpty) return 0.0;

    final int ordemAtual = faseAtual['ordem'] as int? ?? 1;
    final int totalFases = fases.length;

    // Subtraímos 1 à ordem atual para garantir que o progresso só conta as fases concluídas.
    // Se estiver na Fase 1, o progresso é 0%. Só passa para a percentagem seguinte quando a Fase 1 for concluída.
    return ((ordemAtual - 1) / totalFases).clamp(0.0, 1.0);
  }

  bool _verificarSeAtrasada(String? dataEntregaStr) {
    if (dataEntregaStr == null) return false;
    try {
      final dataEntrega = DateTime.parse(dataEntregaStr);
      final hoje = DateTime.now();
      final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
      return hojeSemHoras.isAfter(dataEntrega);
    } catch (_) {
      return false;
    }
  }

  Future<void> _cancelarOrdem(int id) async {
    try {
      setState(() => _isLoading = true);
      await _supabase.from('encomendas').delete().eq('id', id);
      _mostrarMensagem('Ordem de produção cancelada e removida com sucesso!');
      _carregarDados(mostrarLoader: true);
    } catch (e) {
      _mostrarMensagem('Erro ao cancelar ordem: $e', eErro: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarEdicaoOrdem(int id, String novaData, int? novaFaseId) async {
    try {
      setState(() => _isLoading = true);
      
      final dadosAtualizacao = {
        'data_entrega': novaData,
        'fase_atual_id': novaFaseId,
      };

      await _supabase.from('encomendas').update(dadosAtualizacao).eq('id', id);
      _mostrarMensagem('Ordem updated com sucesso!');
      _carregarDados(mostrarLoader: true);
    } catch (e) {
      _mostrarMensagem('Erro ao editar ordem: $e', eErro: true);
      setState(() => _isLoading = false);
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

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
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
                        'Ordens de Produção em Curso',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Pesquisar por Código de Rastreio ou Cliente...',
                          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                          fillColor: Colors.grey.shade100,
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _encomendasFiltradas.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'Não existem ordens de produção ativas correspondentes à pesquisa.',
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _encomendasFiltradas.length,
                              itemBuilder: (context, index) {
                                return _buildOrdemCard(_encomendasFiltradas[index]);
                              },
                            ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOrdemCard(Map<String, dynamic> enc) {
    final idFormatado = 'ORD-2026-${enc['id'].toString().padLeft(3, '0')}';
    final String codigoRastreio = enc['codigo_rastreio'] ?? 'N/A';
    final String nomeCliente = enc['clientes'] != null ? enc['clientes']['nome_cliente'] : 'N/A';
    final String nomeProduto = enc['tipos_produto'] != null ? enc['tipos_produto']['nome_tipo_produto'] : 'N/A';
    final String faseNome = enc['fase_atual'] != null ? enc['fase_atual']['nome_fase_padrao'] : 'N/A';
    final String dataEntrega = enc['data_entrega'] ?? '';

    final double progresso = _calcularProgresso(enc);
    final int progressoPercentagem = (progresso * 100).toInt();
    final bool atrasada = _verificarSeAtrasada(dataEntrega);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
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
                            idFormatado,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              codigoRastreio,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                          ),
                          if (atrasada) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                'Atrasada',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                              ),
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(nomeCliente, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                      Text(nomeProduto, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      const SizedBox(height: 12),
                      Text(
                        'Fase Atual: $faseNome',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          dataEntrega,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _abrirDialogEditar(enc),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.black87),
                          label: const Text('Editar', style: TextStyle(color: Colors.black87, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _confirmarCancelamento(enc['id'], idFormatado),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.black87),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$progressoPercentagem% concluído',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    )
                  ],
                ),
              ],
            ),
          ),
          
          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF111625)),
            ),
          ),
        ],
      ),
    );
  }

  // --- POPUPS E DIALOGS ---

  void _confirmarCancelamento(int id, String refOrdem) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancelar Ordem de Produção'),
          content: Text('Tem a certeza de que deseja cancelar e apagar a ordem $refOrdem do sistema?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Não')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _cancelarOrdem(id);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Sim, Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _abrirDialogEditar(Map<String, dynamic> enc) {
    final dataController = TextEditingController(text: enc['data_entrega']);
    final int prodId = enc['tipos_produtos_id'] as int;
    final fasesDisponiveis = _fasesPorProduto[prodId] ?? [];
    
    dynamic faseSelecionadaLocal;
    try {
      faseSelecionadaLocal = fasesDisponiveis.firstWhere((f) => f['id'] == enc['fase_atual_id']);
    } catch (_) {
      faseSelecionadaLocal = fasesDisponiveis.isNotEmpty ? fasesDisponiveis.first : null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Ordem de Produção'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dataController,
                    decoration: const InputDecoration(
                      labelText: 'Data de Entrega (AAAA-MM-DD)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final DateTime? data = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(dataController.text) ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (data != null) {
                        setDialogState(() {
                          dataController.text = "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<dynamic>(
                    value: faseSelecionadaLocal,
                    decoration: const InputDecoration(labelText: 'Fase Atual de Produção'),
                    items: [
                      ...fasesDisponiveis.map((f) {
                        return DropdownMenuItem<dynamic>(
                          value: f,
                          child: Text('Fase ${f['ordem']}: ${f['nome_fase_padrao'] ?? ''}'),
                        );
                      }),
                      const DropdownMenuItem<dynamic>(
                        value: null,
                        child: Text('🏁 Dar como Concluída'),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => faseSelecionadaLocal = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _salvarEdicaoOrdem(
                      enc['id'],
                      dataController.text.trim(),
                      faseSelecionadaLocal?['id'],
                    );
                  },
                  child: const Text('Gravar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}