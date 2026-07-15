import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'popups/bloquear_tarefa_screen.dart';

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

  Future<void> _carregarFilaTrabalho() async {
    try {
      // Nome exato da tabela no singular: tipos_produto
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

      // Buscar incidências ativas correlacionando com o histórico
      final incidenciasData = await _supabase
          .from('incidencias')
          .select('historico_producao ( encomenda_id )');

      final Set<int> idsBloqueados = {};
      for (var inc in incidenciasData) {
        if (inc['historico_producao'] != null) {
          idsBloqueados.add(inc['historico_producao']['encomenda_id'] as int);
        }
      }

      setState(() {
        _encomendasAtivas = data.map((enc) {
          final isBloqueada = idsBloqueados.contains(enc['id']);
          return {...enc, 'bloqueada': isBloqueada};
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar fila: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _concluirFase(Map<String, dynamic> encomenda) async {
    final faseAtual = encomenda['fases_padrao'];
    final ordemAtual = faseAtual['ordem'];
    final tipoProdutoId = faseAtual['tipos_produto_id'];
    final encomendaId = encomenda['id'];

    setState(() => _isLoading = true);

    try {
      final proximaFaseData = await _supabase
          .from('fases_padrao')
          .select('id, nome_fase_padrao')
          .eq('tipos_produto_id', tipoProdutoId)
          .eq('ordem', ordemAtual + 1)
          .maybeSingle();

      final utilizadorId = _supabase.auth.currentUser?.id;

      await _supabase.from('historico_producao').insert({
        'encomenda_id': encomendaId,
        'fase_concluida_id': faseAtual['id'],
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      if (proximaFaseData != null) {
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': proximaFaseData['id']})
            .eq('id', encomendaId);
      } else {
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': null})
            .eq('id', encomendaId);
      }

      _carregarFilaTrabalho();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao evoluir fase: $e'), backgroundColor: Colors.red),
      );
      setState(() => _isLoading = false);
    }
  }

  void _abrirPopupIncidencia(Map<String, dynamic> encomenda) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BloquearTarefaPopup(
        encomendaId: encomenda['id'],
        codigoRastreio: encomenda['codigo_rastreio'],
        faseAtualId: encomenda['fases_padrao']['id'],
      ),
    );

    if (result == true) _carregarFilaTrabalho();
  }

  @override
  Widget build(BuildContext context) {
    final larguraEcra = MediaQuery.of(context).size.width;
    final crossAxisCount = larguraEcra > 800 ? 2 : 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal do Operador - Chão de Fábrica'),
        backgroundColor: Colors.orange.shade50,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _encomendasAtivas.isEmpty
              ? const Center(child: Text('Nenhum trabalho pendente.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 240,
                  ),
                  itemCount: _encomendasAtivas.length,
                  itemBuilder: (context, index) {
                    final enc = _encomendasAtivas[index];
                    final cliente = enc['clientes']?['nome_cliente'] ?? 'Sem Cliente';
                    final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto';
                    final faseAtual = enc['fases_padrao']?['nome_fase_padrao'] ?? 'Finalizado';
                    final isBloqueada = enc['bloqueada'] ?? false;

                    return Card(
                      color: isBloqueada ? Colors.red.shade50 : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isBloqueada ? BorderSide(color: Colors.red.shade300, width: 2) : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(enc['codigo_rastreio'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                Chip(
                                  label: Text(isBloqueada ? 'BLOQUEADA' : faseAtual),
                                  backgroundColor: isBloqueada ? Colors.red.shade100 : Colors.orange.shade100,
                                ),
                              ],
                            ),
                            const Divider(),
                            Text('Cliente: $cliente'),
                            Text('Produto: $produto', style: const TextStyle(fontWeight: FontWeight.w500)),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: isBloqueada ? null : () => _abrirPopupIncidencia(enc),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                                    icon: const Icon(Icons.report_problem),
                                    label: const Text('Problema'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: isBloqueada ? null : () => _concluirFase(enc),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('Concluir'),
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
    );
  }
}