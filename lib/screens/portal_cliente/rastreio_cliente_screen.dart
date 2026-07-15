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

  // RF011: Procura a encomenda e as suas fases correspondentes para montar o progresso visual
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
      // 1. Procurar a encomenda pelo código de rastreio único
      final encomendaData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
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

      // 2. Procurar todas as fases padrão associadas a este tipo de produto para montar a linha temporal
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rastreio de Encomenda'),
        backgroundColor: Colors.deepPurple.shade50,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 72,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Acompanhe o seu Pedido',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Insira o código de rastreio que recebeu para consultar o estado de produção em tempo real.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                
                // Campo para inserção do código
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codigoController,
                        decoration: const InputDecoration(
                          labelText: 'Código de Rastreio (Ex: TRC-XXXXXX)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _buscarRastreio(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _buscarRastreio,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                      child: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),

                if (_erro != null)
                  Text(
                    _erro!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),

                // Resultados e Linha Temporal (Máquina de Estados Visual)
                if (_encomenda != null) ...[
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Encomenda: ${_encomenda!['codigo_rastreio']}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 4),
                          Text('Cliente: ${_encomenda!['clientes']?['nome_cliente'] ?? 'N/A'}'),
                          Text('Previsão de Entrega: ${_encomenda!['data_entrega']}'),
                          const Divider(height: 24),
                          const Text(
                            'Progresso de Fabrico:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),

                          // Desenhar a Linha Temporal das Fases
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _fasesDoProduto.length,
                            itemBuilder: (context, index) {
                              final fase = _fasesDoProduto[index];
                              final faseId = fase['id'];
                              final faseAtualId = _encomenda!['fase_atual_id'];
                              
                              // Lógica para determinar o estado de cada fase na lista
                              bool isFaseAtual = faseId == faseAtualId;
                              
                              // Determinar a ordem lógica para marcar como concluídas as anteriores
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
                                                : Colors.grey,
                                      ),
                                      if (index < _fasesDoProduto.length - 1)
                                        Container(
                                          width: 2,
                                          height: 40,
                                          color: isConcluida ? Colors.green : Colors.grey.shade300,
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
                                            fontWeight: (isFaseAtual || isConcluida)
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isFaseAtual
                                                ? Colors.orange
                                                : isConcluida
                                                    ? Colors.green
                                                    : Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          isConcluida
                                              ? 'Concluída'
                                              : isFaseAtual
                                                  ? 'Fase Atual'
                                                  : 'Pendente',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ]
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