import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

// 📜 1. FORMATADOR COSTUMIZADO (Declarado no escopo global/topo do ficheiro)
class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String clean = newValue.text.replaceAll(RegExp(r'[^\d+]'), '');
    
    StringBuffer sb = StringBuffer();
    int digitIndex = 0;
    
    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (char == '+' && i == 0) {
        sb.write(char);
        continue;
      }
      if (RegExp(r'\d').hasMatch(char)) {
        if (digitIndex == 3 || digitIndex == 6 || digitIndex == 9) {
          sb.write(' ');
        }
        sb.write(char);
        digitIndex++;
      }
    }
    
    final result = sb.toString();
    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _clientesSubscription;

  List<dynamic> _clientes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
    _inicializarSubscricaoRealtime();
  }

  @override
  void dispose() {
    if (_clientesSubscription != null) {
      _supabase.removeChannel(_clientesSubscription!);
    }
    super.dispose();
  }

  // --- LIGAÇÃO À BASE DE DADOS & REALTIME (SUPABASE) ---

  void _inicializarSubscricaoRealtime() {
    _clientesSubscription = _supabase.channel('db-clientes-realtime')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'clientes',
        callback: (payload) => _carregarClientes(),
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'encomendas',
        callback: (payload) => _carregarClientes(),
      );

    _clientesSubscription?.subscribe();
  }

  Future<void> _carregarClientes() async {
    try {
      final data = await _supabase
          .from('clientes')
          .select('id, nome_cliente, contacto, email, ativo, encomendas(id)')
          .order('nome_cliente', ascending: true);

      if (mounted) {
        setState(() {
          _clientes = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      _mostrarMensagem('Erro ao carregar base de dados de clientes: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _inserirCliente(String nome, String email, String contacto, bool ativo) async {
    try {
      setState(() => _isLoading = true);
      // 🛠️ CORREÇÃO: Bloco perfeitamente fechado aqui com });
      await _supabase.from('clientes').insert({
        'nome_cliente': nome,
        'email': email,
        'contacto': contacto,
        'ativo': ativo,
      });
      _mostrarMensagem('Conta de cliente criada com sucesso!');
      _carregarClientes();
    } catch (e) {
      _mostrarMensagem('Erro ao criar cliente: $e', eErro: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarCliente(int id, String nome, String email, String contacto, bool ativo) async {
    try {
      setState(() => _isLoading = true);
      await _supabase.from('clientes').update({
        'nome_cliente': nome,
        'email': email,
        'contacto': contacto,
        'ativo': ativo,
      }).eq('id', id);

      _mostrarMensagem('Dados do cliente updated!');
      _carregarClientes();
    } catch (e) {
      _mostrarMensagem('Erro ao atualizar cliente: $e', eErro: true);
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

  String _formatarTelefone(String contacto) {
    String clean = contacto.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return 'Sem contacto';
    
    StringBuffer sb = StringBuffer();
    int digitIndex = 0;
    
    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (char == '+' && i == 0) {
        sb.write(char);
        continue;
      }
      if (RegExp(r'\d').hasMatch(char)) {
        if (digitIndex == 3 || digitIndex == 6 || digitIndex == 9) {
          sb.write(' ');
        }
        sb.write(char);
        digitIndex++;
      }
    }
    return sb.toString();
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Base de Dados de Clientes',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Gestão de informações e credenciais de acesso',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _abrirDialogCliente(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF111625),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Criar Conta de Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      _clientes.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('Nenhum cliente registado na base de dados.', style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          : Column(
                              children: [
                                _buildTableHeader(),
                                const Divider(height: 1, thickness: 1),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _clientes.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                                  itemBuilder: (context, index) {
                                    return _buildClienteRow(_clientes[index]);
                                  },
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: const [
          Expanded(
            flex: 3,
            child: Text('Nome do Cliente', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Contacto', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Histórico de Encomendas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Acesso ao Portal', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteRow(Map<String, dynamic> cliente) {
    final String nome = cliente['nome_cliente'] ?? 'N/A';
    final String email = cliente['email'] ?? 'Sem email'; 
    final bool ativo = cliente['ativo'] ?? true;          

    final String contacto = _formatarTelefone(cliente['contacto'] ?? '');

    final List<dynamic> encomendasAssociadas = cliente['encomendas'] ?? [];
    final int totalEncomendas = encomendasAssociadas.length;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nome,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.email_outlined, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Text(
                      email,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(
                  contacto,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off_rounded, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        '$totalEncomendas encomendas',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: ativo ? const Color(0xFF707070) : const Color(0xFFEAEAEA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ativo ? 'Ativo' : 'Inativo',
                    style: TextStyle(
                      color: ativo ? Colors.white : Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _abrirDialogCliente(clienteExistente: cliente),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.black87),
                label: const Text('Editar Dados', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDialogCliente({Map<String, dynamic>? clienteExistente}) {
    final nomeController = TextEditingController(text: clienteExistente?['nome_cliente'] ?? '');
    final emailController = TextEditingController(text: clienteExistente?['email'] ?? '');
    
    final contactoController = TextEditingController(
      text: clienteExistente != null ? _formatarTelefone(clienteExistente['contacto'] ?? '') : '',
    );
    bool acessoAtivo = clienteExistente?['ativo'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(clienteExistente == null ? 'Criar Conta de Cliente' : 'Editar Dados do Cliente'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeController,
                    decoration: const InputDecoration(labelText: 'Nome do Cliente / Empresa *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email de Contacto'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactoController,
                    decoration: const InputDecoration(labelText: 'Contacto Telefónico *'),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(16),
                      TelefoneInputFormatter(), // 👈 Ativado e limpo!
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Acesso ao Portal de Rastreio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(acessoAtivo ? 'Cliente consegue rastrear encomendas' : 'Acesso temporariamente bloqueado'),
                    value: acessoAtivo,
                    activeThumbColor: Colors.black87, // 👈 Atualizado para evitar warnings
                    onChanged: (val) {
                      setDialogState(() => acessoAtivo = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.isNotEmpty && contactoController.text.isNotEmpty) {
                      Navigator.pop(context);
                      if (clienteExistente == null) {
                        _inserirCliente(
                          nomeController.text.trim(),
                          emailController.text.trim(),
                          contactoController.text.trim(),
                          acessoAtivo,
                        );
                      } else {
                        _atualizarCliente(
                          clienteExistente['id'] as int,
                          nomeController.text.trim(),
                          emailController.text.trim(),
                          contactoController.text.trim(),
                          acessoAtivo,
                        );
                      }
                    }
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