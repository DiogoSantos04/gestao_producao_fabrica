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
  String? _nomeCliente;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  // RF013: Procura o histórico de encomendas do cliente autenticado em tempo real
  Future<void> _carregarHistorico() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _erro = 'Utilizador não autenticado.';
          _isLoading = false;
        });
        return;
      }

      // 1. Ir à tabela 'utilizadores' buscar os dados associados ao UUID do Auth
      final utilizadorData = await _supabase
          .from('utilizadores')
          .select('nome_utilizador, email')
          .eq('utilizador_id', user.id)
          .maybeSingle();

      if (utilizadorData == null) {
        setState(() {
          _erro = 'Perfil de utilizador não encontrado.';
          _isLoading = false;
        });
        return;
      }

      // 2. Procurar na tabela 'clientes' pelo registo com o mesmo nome ou email
      // (Ponte lógica entre utilizador autenticado e o registo de cliente)
      final clienteData = await _supabase
          .from('clientes')
          .select('id, nome_cliente')
          .eq('nome_cliente', utilizadorData['nome_utilizador'])
          .maybeSingle();

      if (clienteData == null) {
        setState(() {
          _nomeCliente = utilizadorData['nome_utilizador'];
          _encomendasCliente = []; // Cliente não tem encomendas vinculadas ainda
          _isLoading = false;
        });
        return;
      }

      _nomeCliente = clienteData['nome_cliente'];

      // 3. Procurar as encomendas associadas a este cliente
      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produto ( nome_tipo_produto ),
            fases_padrao!fase_atual_id ( nome_fase_padrao )
          ''')
          .eq('cliente_id', clienteData['id']);

      setState(() {
        _encomendasCliente = encomendasData;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Erro ao carregar histórico: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Área Reservada do Cliente'),
        backgroundColor: Colors.blue.shade50,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _carregarHistorico();
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Text(
                    _erro!,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Cabeçalho de Boas-vindas personalizado
                          Card(
                            color: Colors.deepPurple.shade50,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.deepPurple.shade100),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    child: Text(_nomeCliente != null ? _nomeCliente![0].toUpperCase() : 'C'),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Olá, $_nomeCliente!',
                                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                        ),
                                        const Text(
                                          'Aqui pode gerir e acompanhar o progresso das suas ordens de fabrico.',
                                          style: TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'O Meu Histórico de Encomendas',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          ),
                          const SizedBox(height: 12),
                          
                          // Listagem das encomendas do cliente
                          Expanded(
                            child: _encomendasCliente.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Ainda não tem encomendas registadas no sistema.',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _encomendasCliente.length,
                                    itemBuilder: (context, index) {
                                      final enc = _encomendasCliente[index];
                                      final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto';
                                      final faseAtual = enc['fases_padrao']?['nome_fase_padrao'] ?? 'Finalizado';

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.all(16),
                                          leading: const Icon(Icons.receipt_long, color: Colors.deepPurple, size: 40),
                                          title: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                enc['codigo_rastreio'],
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                              Chip(
                                                label: Text(faseAtual),
                                                backgroundColor: faseAtual == 'Finalizado' 
                                                    ? Colors.green.shade100 
                                                    : Colors.blue.shade100,
                                              ),
                                            ],
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 8),
                                              Text('Artigo: $produto', style: const TextStyle(fontWeight: FontWeight.w500)),
                                              Text('Previsão de entrega: ${enc['data_entrega']}'),
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
                  ),
                ),
    );
  }
}