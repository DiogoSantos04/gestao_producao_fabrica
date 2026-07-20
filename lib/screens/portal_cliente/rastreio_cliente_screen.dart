import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RastreioClienteScreen extends StatefulWidget {
  const RastreioClienteScreen({super.key});

  @override
  State<RastreioClienteScreen> createState() => _RastreioClienteScreenState();
}

class _RastreioClienteScreenState extends State<RastreioClienteScreen> {
  final _supabase = Supabase.instance.client;
  final _codigoController = TextEditingController();
  
  bool _isLoading = false;
  Map<String, dynamic>? _encomenda;
  List<dynamic> _fasesDoProduto = [];
  String? _erro;

  @override
  void dispose() {
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _buscarRastreio() async {
    final codigo = _codigoController.text.trim().toUpperCase();
    if (codigo.isEmpty) return;

    setState(() {
      _isLoading = true;
      _encomenda = null;
      _fasesDoProduto = [];
      _erro = null;
    });

    try {
      final encomendaData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            tipos_produto ( nome_tipo_produto ),
            clientes ( nome_cliente )
          ''')
          .eq('codigo_rastreio', codigo)
          .maybeSingle();

      if (encomendaData == null) {
        setState(() {
          _erro = 'Nenhuma encomenda encontrada com o código informado.';
          _isLoading = false;
        });
        return;
      }

      final tipoProdutoId = encomendaData['tipos_produtos_id'];
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('id, nome_fase_padrao, ordem')
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem', ascending: true);

      setState(() {
        _encomenda = encomendaData;
        _fasesDoProduto = fasesData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao realizar pesquisa: $e';
        _isLoading = false;
      });
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Rastreio de Encomendas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Insira o código de rastreio para acompanhar o estado do seu pedido em tempo real.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                ),
                const SizedBox(height: 28),
                
                // Card de Pesquisa
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codigoController,
                            decoration: const InputDecoration(
                              hintText: 'Código de Rastreio (Ex: TRC-XXXXXX)',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search, color: Color(0xFF94A3B8)),
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _buscarRastreio(),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _buscarRastreio,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),

                if (_erro != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),

                // Cartão com Linha Temporal do Progresso
                if (_encomenda != null) ...[
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _encomenda!['codigo_rastreio'],
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1E293B)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _encomenda!['tipos_produto']?['nome_tipo_produto'] ?? 'Artigo',
                                  style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.event, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 6),
                              Text(
                                'Data Prevista de Entrega: ${_formatarData(_encomenda!['data_entrega'])}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          const Text(
                            'Etapas de Fabrico',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 20),

                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _fasesDoProduto.length,
                            itemBuilder: (context, index) {
                              final fase = _fasesDoProduto[index];
                              final faseId = fase['id'];
                              final faseAtualId = _encomenda!['fase_atual_id'];
                              
                              bool isFaseAtual = faseId == faseAtualId;
                              final ordemFaseAtual = _fasesDoProduto.firstWhere(
                                (f) => f['id'] == faseAtualId,
                                orElse: () => {'ordem': 999},
                              )['ordem'];

                              bool isConcluida = fase['ordem'] < ordemFaseAtual;

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    children: [
                                      Icon(
                                        isConcluida
                                            ? Icons.check_circle
                                            : isFaseAtual
                                                ? Icons.play_circle_filled
                                                : Icons.radio_button_unchecked,
                                        color: isConcluida
                                            ? Colors.green
                                            : isFaseAtual
                                                ? Colors.orange
                                                : Colors.grey.shade300,
                                        size: 22,
                                      ),
                                      if (index < _fasesDoProduto.length - 1)
                                        Container(
                                          width: 2,
                                          height: 36,
                                          color: isConcluida ? Colors.green : Colors.grey.shade200,
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fase['nome_fase_padrao'],
                                          style: TextStyle(
                                            fontWeight: (isFaseAtual || isConcluida) ? FontWeight.bold : FontWeight.normal,
                                            color: isFaseAtual
                                                ? Colors.orange.shade800
                                                : isConcluida
                                                    ? Colors.green.shade800
                                                    : const Color(0xFF64748B),
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          isConcluida
                                              ? 'Concluída'
                                              : isFaseAtual
                                                  ? 'Em Processamento'
                                                  : 'Pendente',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}