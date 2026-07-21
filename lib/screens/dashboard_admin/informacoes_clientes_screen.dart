import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

// 📜 FORMATADOR COSTUMIZADO PARA TELEFONE
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

  // 🔍 CONTROLADORES E ESTADOS DE FILTRAGEM
  final TextEditingController _searchController = TextEditingController();
  String _pesquisaQuery = '';
  String _filtroEstado = 'Todos'; // 'Todos', 'Ativos', 'Inativos', 'Com Encomendas'

  @override
  void initState() {
    super.initState();
    _carregarClientes();
    _inicializarSubscricaoRealtime();

    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _pesquisaQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_clientesSubscription != null) {
      _supabase.removeChannel(_clientesSubscription!);
    }
    super.dispose();
  }

  // --- HELPERS ULTRA-SEGURA CONTRA ERROS DE TIPO NO FLUTTER WEB ---

  int _obterTotalEncomendas(dynamic cliente) {
    if (cliente == null || cliente['encomendas'] == null) return 0;
    final enc = cliente['encomendas'];
    if (enc is List) {
      return enc.length;
    }
    return 0;
  }

  bool _temEncomendas(dynamic cliente) {
    return _obterTotalEncomendas(cliente) > 0;
  }

  // --- GETTER QUE DEVOLVE OS CLIENTES FILTRADOS EM TEMPO REAL ---

  List<dynamic> get _clientesFiltrados {
    return _clientes.where((cliente) {
      if (cliente == null) return false;

      final String nome = (cliente['nome_cliente'] ?? '').toString().toLowerCase();
      final String email = (cliente['email'] ?? '').toString().toLowerCase();
      final String contacto = (cliente['contacto'] ?? '').toString().toLowerCase();
      final bool ativo = cliente['ativo'] == true;

      // 1. Filtragem por Texto de Pesquisa
      final bool correspondePesquisa = _pesquisaQuery.isEmpty ||
          nome.contains(_pesquisaQuery) ||
          email.contains(_pesquisaQuery) ||
          contacto.contains(_pesquisaQuery);

      if (!correspondePesquisa) return false;

      // 2. Filtragem por Estado / Encomendas
      if (_filtroEstado == 'Ativos') {
        return ativo == true;
      } else if (_filtroEstado == 'Inativos') {
        return ativo == false;
      } else if (_filtroEstado == 'Com Encomendas') {
        return _temEncomendas(cliente);
      }

      return true;
    }).toList();
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

      _mostrarMensagem('Dados do cliente atualizados!');
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
    final listaExibida = _clientesFiltrados;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📊 CARTÕES DE MÉTRICAS (KPIs DO CARTEIRA DE CLIENTES)
                  _buildKpiCards(),
                  const SizedBox(height: 24),

                  // TABELA DE CLIENTES & FERRAMENTAS DE PESQUISA
                  Card(
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
                          // CABEÇALHO DO CARD COM BOTÃO
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
                          const SizedBox(height: 24),

                          // 🔍 BARRA DE PESQUISA E FILTROS RÁPIDOS
                          _buildBarraFiltros(),
                          const SizedBox(height: 24),

                          // TABELA OU MENSAGEM VAZIA
                          if (_clientes.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('Nenhum cliente registado na base de dados.', style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          else if (listaExibida.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.search_off_rounded, size: 36, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Nenhum cliente encontrado com os filtros aplicados.',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Column(
                              children: [
                                _buildTableHeader(),
                                const Divider(height: 1, thickness: 1),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: listaExibida.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                                  itemBuilder: (context, index) {
                                    return _buildClienteRow(listaExibida[index]);
                                  },
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // --- BARRA DE PESQUISA E FILTROS RÁPIDOS ---

  Widget _buildBarraFiltros() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool eMobile = constraints.maxWidth < 650;

        return eMobile
            ? Column(
                children: [
                  _buildCampoPesquisa(),
                  const SizedBox(height: 12),
                  _buildDropdownFiltro(),
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 3, child: _buildCampoPesquisa()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildDropdownFiltro()),
                ],
              );
      },
    );
  }

  Widget _buildCampoPesquisa() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Pesquisar por nome, email ou contacto...',
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.black54),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => _searchController.clear(),
              )
            : null,
        fillColor: Colors.grey.shade100,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildDropdownFiltro() {
    return DropdownButtonFormField<String>(
      value: _filtroEstado,
      decoration: InputDecoration(
        fillColor: Colors.grey.shade100,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: const [
        DropdownMenuItem(value: 'Todos', child: Text('Todos os Clientes', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'Ativos', child: Text('Ativos no Portal', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'Inativos', child: Text('Inativos', style: TextStyle(fontSize: 13))),
        DropdownMenuItem(value: 'Com Encomendas', child: Text('Com Encomendas', style: TextStyle(fontSize: 13))),
      ],
      onChanged: (val) {
        if (val != null) setState(() => _filtroEstado = val);
      },
    );
  }

  // --- WIDGET DOS CARTÕES DE MÉTRICAS (KPIS) ---

  Widget _buildKpiCards() {
    final int totalClientes = _clientes.length;
    final int ativosPortal = _clientes.where((c) => c['ativo'] == true).length;
    final int comEncomendas = _clientes.where((c) => _temEncomendas(c)).length;
    final int totalEncomendas = _clientes.fold<int>(0, (sum, c) => sum + _obterTotalEncomendas(c));

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool eWide = constraints.maxWidth > 900;
        final double cardWidth = eWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Total de Clientes',
              valor: '$totalClientes',
              subtitulo: 'Empresas registadas',
              icone: Icons.business_rounded,
              corIcone: const Color(0xFF111625),
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Acesso ao Portal',
              valor: '$ativosPortal',
              subtitulo: 'Contas ativas',
              icone: Icons.verified_user_outlined,
              corIcone: Colors.green.shade700,
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Clientes c/ Encomendas',
              valor: '$comEncomendas',
              subtitulo: 'Com histórico associado',
              icone: Icons.shopping_bag_outlined,
              corIcone: Colors.blue.shade700,
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Volume de Encomendas',
              valor: '$totalEncomendas',
              subtitulo: 'Total acumulado',
              icone: Icons.inventory_2_outlined,
              corIcone: Colors.amber.shade800,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required double largura,
    required String titulo,
    required String valor,
    required String subtitulo,
    required IconData icone,
    required Color corIcone,
  }) {
    return Container(
      width: largura,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  valor,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitulo,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: corIcone.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: corIcone, size: 22),
          ),
        ],
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

  Widget _buildClienteRow(dynamic cliente) {
    final String nome = cliente['nome_cliente'] ?? 'N/A';
    final String email = cliente['email'] ?? 'Sem email'; 
    final bool ativo = cliente['ativo'] == true;          

    final String contacto = _formatarTelefone(cliente['contacto'] ?? '');
    final int totalEncomendas = _obterTotalEncomendas(cliente);

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
                      TelefoneInputFormatter(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Acesso ao Portal de Rastreio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(acessoAtivo ? 'Cliente consegue rastrear encomendas' : 'Acesso temporariamente bloqueado'),
                    value: acessoAtivo,
                    activeColor: Colors.black87,
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