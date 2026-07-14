import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TerminalOperadorScreen extends StatefulWidget {
  const TerminalOperadorScreen({super.key});

  @override
  State<TerminalOperadorScreen> createState() => _TerminalOperadorScreenState();
}

class _TerminalOperadorScreenState extends State<TerminalOperadorScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _encomendasAtivas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarFilaTrabalho();
  }

  // RF007: Consulta a lista de encomendas em produção com detalhes do cliente e fase atual
  Future<void> _carregarFilaTrabalho() async {
    try {
      final data = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            clientes ( nome_cliente ),
            tipos_produto ( nome_tipo_produto ),
            fases_padrao!fase_atual_id ( id, nome_fase_padrao, ordem, tipos_produto_id )
          ''');

      setState(() {
        _encomendasAtivas = data;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar fila: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  // RF008: Atualizar Estado (Avançar para a próxima fase na Máquina de Estados)
  Future<void> _concluirFase(Map<String, dynamic> encomenda) async {
    final faseAtual = encomenda['fases_padrao'];
    final ordemAtual = faseAtual['ordem'];
    final tipoProdutoId = faseAtual['tipos_produto_id'];
    final encomendaId = encomenda['id'];

    setState(() => _isLoading = true);

    try {
      // 1. Procurar a próxima fase padrão (ordem atual + 1)
      final proximaFaseData = await _supabase
          .from('fases_padrao')
          .select('id, nome_fase_padrao')
          .eq('tipos_produto_id', tipoProdutoId)
          .eq('ordem', ordemAtual + 1)
          .maybeSingle();

      // Obter o ID do utilizador autenticado para auditoria no histórico
      final utilizadorId = _supabase.auth.currentUser?.id;

      // Gravar no histórico de produção o encerramento da fase atual
      await _supabase.from('historico_producao').insert({
        'encomenda_id': encomendaId,
        'fase_concluida_id': faseAtual['id'],
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      if (proximaFaseData != null) {
        // Se existe uma próxima fase, atualizamos a encomenda para essa fase
        final proximaFaseId = proximaFaseData['id'];
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': proximaFaseId})
            .eq('id', encomendaId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fase concluída! Encomenda avançou para: ${proximaFaseData['nome_fase_padrao']}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Se não há mais fases, a encomenda está totalmente finalizada
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': null}) // ou outro estado de finalizado conforme o vosso fluxo
            .eq('id', encomendaId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Parabéns! Encomenda totalmente finalizada e pronta para entrega!'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }

      _carregarFilaTrabalho();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao transitar de fase: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Design responsivo com botões grandes estilo tablet para o chão de fábrica
    final larguraEcra = MediaQuery.of(context).size.width;
    final crossAxisCount = larguraEcra > 800 ? 2 : 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal do Operador - Chão de Fábrica'),
        backgroundColor: Colors.orange.shade50,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarFilaTrabalho,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _encomendasAtivas.isEmpty
              ? const Center(child: Text('Nenhum trabalho pendente nesta secção.'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: 220,
                    ),
                    itemCount: _encomendasAtivas.length,
                    itemBuilder: (context, index) {
                      final enc = _encomendasAtivas[index];
                      final cliente = enc['clientes']?['nome_cliente'] ?? 'Sem Cliente';
                      final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto';
                      final faseAtual = enc['fases_padrao']?['nome_fase_padrao'] ?? 'Finalizado';

                      return Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    enc['codigo_rastreio'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple),
                                  ),
                                  Chip(
                                    label: Text(faseAtual),
                                    backgroundColor: Colors.orange.shade100,
                                  ),
                                ],
                              ),
                              const Divider(),
                              Text('Cliente: $cliente', style: const TextStyle(fontSize: 15)),
                              Text('Produto: $produto', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                              const Spacer(),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _concluirFase(enc),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.check_circle_outline),
                                      label: const Text('Concluir Fase', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}