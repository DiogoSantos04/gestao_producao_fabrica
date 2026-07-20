import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SolicitarEncomendaScreen extends StatefulWidget {
  const SolicitarEncomendaScreen({super.key});

  @override
  State<SolicitarEncomendaScreen> createState() => _SolicitarEncomendaScreenState();
}

class _SolicitarEncomendaScreenState extends State<SolicitarEncomendaScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _quantidadeController = TextEditingController(text: '1');
  final _observacoesController = TextEditingController();

  List<dynamic> _tiposProduto = [];
  String? _tipoProdutoSelecionadoId;

  bool _carregandoInicial = true;
  bool _submetendo = false;
  int? _clienteId;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  Future<void> _carregarDadosIniciais() async {
    try {
      final user = _supabase.auth.currentUser;

      // 1. Carrega os tipos de produto diretamente da tabela
      final produtosData = await _supabase
          .from('tipos_produto')
          .select('id, nome_tipo_produto')
          .order('nome_tipo_produto');

      // 2. Procura a correspondência com o cliente logado
      int? clienteIdEncontrado;
      if (user != null) {
        final utilizadorData = await _supabase
            .from('utilizadores')
            .select('nome_utilizador')
            .eq('utilizador_id', user.id)
            .maybeSingle();

        if (utilizadorData != null && utilizadorData['nome_utilizador'] != null) {
          final clienteData = await _supabase
              .from('clientes')
              .select('id')
              .eq('nome_cliente', utilizadorData['nome_utilizador'])
              .maybeSingle();

          if (clienteData != null) {
            clienteIdEncontrado = clienteData['id'] is int 
                ? clienteData['id'] 
                : int.tryParse(clienteData['id'].toString());
          }
        }
      }

      if (mounted) {
        setState(() {
          _tiposProduto = produtosData as List<dynamic>;
          _clienteId = clienteIdEncontrado;
          if (_tiposProduto.isNotEmpty) {
            _tipoProdutoSelecionadoId = _tiposProduto.first['id'].toString();
          }
          _carregandoInicial = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do formulário: $e');
      if (mounted) {
        setState(() => _carregandoInicial = false);
      }
    }
  }

  Future<void> _submeterPedido() async {
    if (!_formKey.currentState!.validate()) return;

    if (_clienteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aviso: O seu utilizador não está associado a um registo na tabela de Clientes.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_tipoProdutoSelecionadoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um artigo da lista.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submetendo = true);

    try {
      final quantidade = int.parse(_quantidadeController.text.trim());
      final observacoes = _observacoesController.text.trim();

      await _supabase.from('pedidos_encomenda').insert({
        'cliente_id': _clienteId,
        'tipo_produto_id': int.parse(_tipoProdutoSelecionadoId!),
        'quantidade': quantidade,
        'observacoes': observacoes.isEmpty ? null : observacoes,
        'estado': 'Pendente',
      });

      if (mounted) {
        setState(() {
          _submetendo = false;
          _observacoesController.clear();
          _quantidadeController.text = '1';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido enviado com sucesso! O Administrador irá analisar a solicitação.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao submeter pedido: $e');
      if (mounted) {
        setState(() => _submetendo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao submeter pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _carregandoInicial
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32.0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Solicitar Nova Encomenda',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Selecione o artigo pretendido e submeta o pedido para a nossa equipa de produção.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 32),

                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Artigo / Tipo de Produto',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 8),

                                DropdownButtonFormField<String>(
                                  value: _tipoProdutoSelecionadoId,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.deepPurple),
                                  ),
                                  hint: const Text('Selecione um artigo'),
                                  items: _tiposProduto.map((prod) {
                                    return DropdownMenuItem<String>(
                                      value: prod['id'].toString(),
                                      child: Text(prod['nome_tipo_produto'].toString()),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() => _tipoProdutoSelecionadoId = val);
                                  },
                                ),
                                const SizedBox(height: 20),

                                const Text(
                                  'Quantidade Pretendida',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _quantidadeController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.format_list_numbered, color: Colors.deepPurple),
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Insira a quantidade.';
                                    final n = int.tryParse(val.trim());
                                    if (n == null || n <= 0) return 'Insira um valor maior que 0.';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 20),

                                const Text(
                                  'Observações / Especificações Especiais',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _observacoesController,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    hintText: 'Escreva detalhes adicionais sobre cores, acabamentos ou prazos pretendidos...',
                                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(height: 32),

                                ElevatedButton.icon(
                                  onPressed: _submetendo ? null : _submeterPedido,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(50),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: _submetendo
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.send_rounded),
                                  label: Text(
                                    _submetendo ? 'A Enviar Pedido...' : 'Submeter Pedido de Encomenda',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}