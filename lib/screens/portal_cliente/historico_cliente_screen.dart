import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoClienteScreen extends StatefulWidget {
  const HistoricoClienteScreen({super.key});

  @override
  State<HistoricoClienteScreen> createState() => _HistoricoClienteScreenState();
}

class _HistoricoClienteScreenState extends State<HistoricoClienteScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _encomendasCliente = [];
  bool _isLoading = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  Future<void> _carregarHistorico() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() { _erro = 'Utilizador não autenticado.'; _isLoading = false; });
        return;
      }

      // 1. Procura o perfil do utilizador
      final utilizadorData = await _supabase
          .from('utilizadores')
          .select('nome_utilizador')
          .eq('utilizador_id', user.id)
          .maybeSingle();

      if (utilizadorData == null) {
        if (mounted) setState(() { _erro = 'Perfil não encontrado.'; _isLoading = false; });
        return;
      }

      // 2. Procura o cliente comercial correspondente
      final clienteData = await _supabase
          .from('clientes')
          .select('id')
          .eq('nome_cliente', utilizadorData['nome_utilizador'])
          .maybeSingle();

      if (clienteData == null) {
        if (mounted) setState(() { _encomendasCliente = []; _isLoading = false; });
        return;
      }

      // 3. Query segura sem relacionamentos complexos aninhados que possam falhar
      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            tipos_produto ( nome_tipo_produto )
          ''')
          .eq('cliente_id', clienteData['id']);

      if (mounted) {
        setState(() {
          _encomendasCliente = encomendasData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar o histórico de encomendas.';
          _isLoading = false;
        });
      }
    }
  }

  String _formatarData(String? isoString) {
    if (isoString == null) return 'A definir';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(_erro!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Histórico de Encomendas',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Consulte todas as suas encomendas e o seu estado de fabrico.',
                        style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 32),

                      Expanded(
                        child: _encomendasCliente.isEmpty
                            ? const Center(
                                child: Text('Ainda não tem encomendas registadas.', style: TextStyle(color: Colors.grey)),
                              )
                            : ListView.builder(
                                itemCount: _encomendasCliente.length,
                                itemBuilder: (context, index) {
                                  final enc = _encomendasCliente[index];
                                  final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Artigo';

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    color: Colors.white,
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.shade50,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.receipt_long, color: Colors.deepPurple, size: 24),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  enc['codigo_rastreio'] ?? 'Sem Código',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                                const SizedBox(height: 4),
                                                Text('Artigo: $produto', style: const TextStyle(color: Color(0xFF475569))),
                                                Text(
                                                  'Previsão de Entrega: ${_formatarData(enc['data_entrega'])}',
                                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}