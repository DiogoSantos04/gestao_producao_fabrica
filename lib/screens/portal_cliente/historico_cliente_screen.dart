import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../login_screen.dart';

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

      // 1. Procura o perfil do utilizador logado
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

      // 2. Procura a correspondência na tabela de clientes comerciais
      final clienteData = await _supabase
          .from('clientes')
          .select('id, nome_cliente')
          .eq('nome_cliente', utilizadorData['nome_utilizador'])
          .maybeSingle();

      if (clienteData == null) {
        setState(() {
          _nomeCliente = utilizadorData['nome_utilizador'];
          _encomendasCliente = [];
          _isLoading = false;
        });
        return;
      }

      _nomeCliente = clienteData['nome_cliente'];

      // 3. Query Avançada: Traz encomendas, fases e verifica incidências ativas de forma aninhada
      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produto ( nome_tipo_produto ),
            fases_padrao!fase_atual_id ( nome_fase_padrao ),
            historico_producao (
              id,
              incidencias (
                motivo,
                data_registo
              )
            )
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Área Reservada do Cliente', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            tooltip: 'Atualizar dados',
            onPressed: () {
              setState(() => _isLoading = true);
              _carregarHistorico();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Terminar Sessão',
            onPressed: () async {
              await _supabase.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
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
                  padding: const EdgeInsets.all(40.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header de Boas-vindas estilizado
                          Card(
                            color: Colors.deepPurple.shade50,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.deepPurple.shade100),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                    child: Text(
                                      _nomeCliente != null && _nomeCliente!.isNotEmpty 
                                          ? _nomeCliente![0].toUpperCase() 
                                          : 'C',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Olá, $_nomeCliente!',
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Acompanhe abaixo o estado real de fabrico e os alertas das suas ordens.',
                                          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'O Meu Histórico de Encomendas',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 16),
                          
                          Expanded(
                            child: _encomendasCliente.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Ainda não tem encomendas registadas no sistema.',
                                      style: TextStyle(color: Colors.grey, fontSize: 15),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _encomendasCliente.length,
                                    itemBuilder: (context, index) {
                                      final enc = _encomendasCliente[index];
                                      final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto';
                                      final faseAtual = enc['fases_padrao']?['nome_fase_padrao'] ?? 'Finalizado';

                                      // Lógica de deteção de bloqueio e extração do motivo
                                      final List<dynamic> historico = enc['historico_producao'] ?? [];
                                      String? motivoBloqueio;
                                      for (var hp in historico) {
                                        final List<dynamic> incidencias = hp['incidencias'] ?? [];
                                        if (incidencias.isNotEmpty) {
                                          motivoBloqueio = incidencias.first['motivo'];
                                          break;
                                        }
                                      }
                                      final bool isBloqueada = motivoBloqueio != null;

                                      return Card(
                                        margin: const EdgeInsets.only(bottom: 16),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          side: BorderSide(
                                            color: isBloqueada ? Colors.red.shade200 : Colors.grey.shade200,
                                            width: isBloqueada ? 1.5 : 1,
                                          ),
                                        ),
                                        color: Colors.white,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            ListTile(
                                              contentPadding: const EdgeInsets.all(20),
                                              leading: Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: isBloqueada ? Colors.red.shade50 : Colors.deepPurple.shade50,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  isBloqueada ? Icons.warning_amber_rounded : Icons.receipt_long, 
                                                  color: isBloqueada ? Colors.red : Colors.deepPurple, 
                                                  size: 24,
                                                ),
                                              ),
                                              title: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    enc['codigo_rastreio'],
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B)),
                                                  ),
                                                  // Badge Dinâmico (Bloqueada vs Fase de Fabrico)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: isBloqueada 
                                                          ? Colors.red.shade100 
                                                          : (faseAtual == 'Finalizado' ? Colors.green.shade100 : Colors.blue.shade100),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      isBloqueada ? 'BLOQUEADA' : faseAtual,
                                                      style: TextStyle(
                                                        color: isBloqueada 
                                                            ? Colors.red.shade900 
                                                            : (faseAtual == 'Finalizado' ? Colors.green.shade900 : Colors.blue.shade900),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              subtitle: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const SizedBox(height: 8),
                                                  Text('Artigo: $produto', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                                                  const SizedBox(height: 2),
                                                  Text('Previsão de entrega: ${enc['data_entrega']}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                                                ],
                                              ),
                                            ),
                                            
                                            // ADICIONADO: Banner de Incidência visível para o cliente
                                            if (isBloqueada)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius: const BorderRadius.only(
                                                    bottomLeft: Radius.circular(12),
                                                    bottomRight: Radius.circular(12),
                                                  ),
                                                  border: Border(top: BorderSide(color: Colors.red.shade100)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.info_outline, color: Colors.red.shade700, size: 18),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: RichText(
                                                        text: TextSpan(
                                                          style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                                                          children: [
                                                            const TextSpan(
                                                              text: 'Motivo da paragem: ',
                                                              style: TextStyle(fontWeight: FontWeight.bold),
                                                            ),
                                                            TextSpan(text: motivoBloqueio),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
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