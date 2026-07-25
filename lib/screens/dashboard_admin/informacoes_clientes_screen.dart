import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/temas_cores.dart';
import '../../repositories/clientes_repository.dart';

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
  final _clientesRepo = ClientesRepository();
  RealtimeChannel? _clientesSubscription;

  List<dynamic> _clientes = [];
  bool _isLoading = true;

  // 🔍 CONTROLADORES E ESTADOS DE FILTRAGEM
  final TextEditingController _searchController = TextEditingController();
  String _pesquisaQuery = '';
  String _filtroEstado = 'Todos'; // 'Todos', 'Ativos', 'Inativos', 'Com Encomendas'

  // 🗂️ PAINEL LATERAL (DRAWER DETALHES DO CLIENTE)
  dynamic _clienteDetalhesSelecionado;

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
      _clientesRepo.client.removeChannel(_clientesSubscription!);
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

  List<dynamic> _obterListaEncomendas(dynamic cliente) {
    if (cliente == null || cliente['encomendas'] == null) return [];
    final enc = cliente['encomendas'];
    if (enc is List) return enc;
    return [];
  }

  List<dynamic> _obterListaPedidos(dynamic cliente) {
    if (cliente == null || cliente['pedidos_encomenda'] == null) return [];
    final ped = cliente['pedidos_encomenda'];
    if (ped is List) return ped;
    return [];
  }

  // --- GETTER QUE DEVOLVE OS CLIENTES FILTRADOS EM TEMPO REAL ---

  List<dynamic> get _clientesFiltrados {
    return _clientes.where((cliente) {
      if (cliente == null) return false;

      final String nome = (cliente['nome_cliente'] ?? '').toString().toLowerCase();
      final String email = (cliente['email'] ?? '').toString().toLowerCase();
      final String contacto = (cliente['contacto'] ?? '').toString().toLowerCase();
      final String nif = (cliente['nif'] ?? '').toString().toLowerCase();
      final String pessoaContacto = (cliente['pessoa_contacto'] ?? '').toString().toLowerCase();
      final String morada = (cliente['morada'] ?? '').toString().toLowerCase();
      final bool ativo = cliente['ativo'] == true;

      final bool correspondePesquisa = _pesquisaQuery.isEmpty ||
          nome.contains(_pesquisaQuery) ||
          email.contains(_pesquisaQuery) ||
          contacto.contains(_pesquisaQuery) ||
          nif.contains(_pesquisaQuery) ||
          pessoaContacto.contains(_pesquisaQuery) ||
          morada.contains(_pesquisaQuery);

      if (!correspondePesquisa) return false;

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
    _clientesSubscription =
        _clientesRepo.escutarCarteira('db-clientes-realtime', _carregarClientes);
  }

  Future<void> _carregarClientes() async {
    try {
      final data = await _clientesRepo.obterComHistorico();

      if (mounted) {
        setState(() {
          _clientes = data;
          _isLoading = false;

          if (_clienteDetalhesSelecionado != null) {
            final int idAtual = _clienteDetalhesSelecionado['id'];
            final clienteAtualizado = _clientes.firstWhere((c) => c['id'] == idAtual, orElse: () => null);
            if (clienteAtualizado != null) {
              _clienteDetalhesSelecionado = clienteAtualizado;
            }
          }
        });
      }
    } catch (e) {
      _mostrarMensagem('Erro ao carregar base de dados de clientes: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _inserirCliente({
    required String nome,
    required String email,
    required String contacto,
    required String nif,
    required String pessoaContacto,
    required String morada,
    required bool ativo,
  }) async {
    try {
      setState(() => _isLoading = true);
      await _clientesRepo.criar({
        'nome_cliente': nome,
        'email': email,
        'contacto': contacto,
        'nif': nif,
        'pessoa_contacto': pessoaContacto,
        'morada': morada,
        'ativo': ativo,
      });
      _mostrarMensagem('Conta de cliente criada com sucesso!');
      _carregarClientes();
    } catch (e) {
      _mostrarMensagem('Erro ao criar cliente: $e', eErro: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _atualizarCliente({
    required int id,
    required String nome,
    required String email,
    required String contacto,
    required String nif,
    required String pessoaContacto,
    required String morada,
    required bool ativo,
  }) async {
    try {
      setState(() => _isLoading = true);
      await _clientesRepo.atualizar(id: id, dados: {
        'nome_cliente': nome,
        'email': email,
        'contacto': contacto,
        'nif': nif,
        'pessoa_contacto': pessoaContacto,
        'morada': morada,
        'ativo': ativo,
      });

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
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 📊 CARTÕES DE MÉTRICAS (KPIs DA CARTEIRA DE CLIENTES)
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
                                        'Gestão de informações fiscais, logísticas e credenciais de acesso',
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

                // 🗂️ OVERLAY & PAINEL LATERAL DESLIZANTE DE DETALHES DO CLIENTE
                if (_clienteDetalhesSelecionado != null) ...[
                  GestureDetector(
                    onTap: () => setState(() => _clienteDetalhesSelecionado = null),
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 520,
                    child: _buildDrawerDetalhesCliente(),
                  ),
                ],
              ],
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
        hintText: 'Pesquisar por nome, email, NIF, contacto ou morada...',
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
            child: Text('Cliente & NIF', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text('Contacto / Interlocutor', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Histórico', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
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
    final String nif = cliente['nif'] ?? '';
    final String pessoaContacto = cliente['pessoa_contacto'] ?? '';
    final String morada = cliente['morada'] ?? '';
    final bool ativo = cliente['ativo'] == true;          

    final String contacto = _formatarTelefone(cliente['contacto'] ?? '');
    final int totalEncomendas = _obterTotalEncomendas(cliente);

    return InkWell(
      onTap: () => setState(() => _clienteDetalhesSelecionado = cliente),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // COLUNA 1: NOME DA EMPRESA, NIF & EMAIL (LAYOUT LIMPO E ALINHADO)
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nome,
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (nif.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NIF $nif',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Icon(Icons.email_outlined, size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          email,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (morada.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            morada,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // COLUNA 2: TELEFONE & PESSOA DE CONTACTO
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text(
                        contacto,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  if (pessoaContacto.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 13, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            pessoaContacto,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // COLUNA 3: HISTÓRICO DE ENCOMENDAS
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _clienteDetalhesSelecionado = cliente),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
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
                  ),
                ],
              ),
            ),

            // COLUNA 4: ACESSO AO PORTAL
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

            // COLUNA 5: AÇÕES
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
      ),
    );
  }

  // --- 🗂️ DRAWER LATERAL: PAINEL DE DETALHES DO CLIENTE ---

  Widget _buildDrawerDetalhesCliente() {
    final c = _clienteDetalhesSelecionado;
    if (c == null) return const SizedBox.shrink();

    final String nome = c['nome_cliente'] ?? 'Cliente';
    final String email = c['email'] ?? '';
    final String nif = c['nif'] ?? '';
    final String contacto = _formatarTelefone(c['contacto'] ?? '');
    final String pessoa = c['pessoa_contacto'] ?? '';
    final String morada = c['morada'] ?? '';
    final bool ativo = c['ativo'] == true;

    final List<dynamic> encomendas = _obterListaEncomendas(c);
    final List<dynamic> pedidos = _obterListaPedidos(c);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(-4, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CABEÇALHO DO DRAWER (DESIGN ELEGANTE)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111625),
              border: Border(bottom: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        nome,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => setState(() => _clienteDetalhesSelecionado = null),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (nif.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                        child: Text('NIF: $nif', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ativo ? Colors.green.shade800 : Colors.red.shade800,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ativo ? 'Portal Ativo' : 'Portal Bloqueado',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // CONTEÚDO DO DRAWER COM SCROLL
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DADOS CADASTRAIS, FISCAIS E LOGÍSTICOS
                  const Text('Informações Fiscais e Logísticas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        if (nif.isNotEmpty) ...[
                          _buildLinhaDetalhe(Icons.badge_outlined, 'NIF / NIPC', nif),
                          const Divider(height: 16),
                        ],
                        _buildLinhaDetalhe(Icons.email_outlined, 'Email', email.isNotEmpty ? email : 'Não registado'),
                        const Divider(height: 16),
                        _buildLinhaDetalhe(Icons.phone_outlined, 'Telefone', contacto),
                        if (pessoa.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildLinhaDetalhe(Icons.person_outline_rounded, 'Interlocutor', pessoa),
                        ],
                        if (morada.isNotEmpty) ...[
                          const Divider(height: 16),
                          _buildLinhaDetalhe(Icons.location_on_outlined, 'Morada Carga', morada),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // SECÇÃO: PEDIDOS DA APP B2B
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Pedidos da Aplicação B2B', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Text('${pedidos.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (pedidos.isEmpty)
                    Text('Nenhum pedido submetido na app.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic))
                  else
                    Column(
                      children: pedidos.map((p) {
                        final String prod = p['tipos_produto']?['nome_tipo_produto'] ?? 'Produto';
                        final String estado = p['estado'] ?? 'Pendente';
                        final int qtd = p['quantidade'] ?? 1;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prod, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text('Qtd: $qtd unidades', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                                child: Text(estado, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 28),

                  // SECÇÃO: HISTÓRICO DE ENCOMENDAS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Ordens de Produção Lançadas', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                        child: Text('${encomendas.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (encomendas.isEmpty)
                    Text('Nenhuma ordem de produção associada.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic))
                  else
                    Column(
                      children: encomendas.map((e) {
                        final String cod = e['codigo_rastreio'] ?? 'TRC-N/A';
                        final String prod = e['tipos_produto']?['nome_tipo_produto'] ?? 'Produto';
                        final String dataEnt = e['data_entrega'] ?? '';
                        final int qtd = e['quantidade'] ?? 1;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cod, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                                  Text('$prod • Qtd: $qtd', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                ],
                              ),
                              Text(dataEnt, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaDetalhe(IconData icone, String titulo, String valor) {
    return Row(
      children: [
        Icon(icone, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(titulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // --- DIÁLOGO DE CRIAÇÃO / EDIÇÃO DE CLIENTE ---

  void _abrirDialogCliente({Map<String, dynamic>? clienteExistente}) {
    final nomeController = TextEditingController(text: clienteExistente?['nome_cliente'] ?? '');
    final emailController = TextEditingController(text: clienteExistente?['email'] ?? '');
    final nifController = TextEditingController(text: clienteExistente?['nif'] ?? '');
    final pessoaContactoController = TextEditingController(text: clienteExistente?['pessoa_contacto'] ?? '');
    final moradaController = TextEditingController(text: clienteExistente?['morada'] ?? '');

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
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 480,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nomeController,
                        decoration: const InputDecoration(labelText: 'Nome do Cliente / Empresa *'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: nifController,
                              decoration: const InputDecoration(labelText: 'NIF / NIPC', hintText: '9 dígitos'),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(9),
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: emailController,
                              decoration: const InputDecoration(labelText: 'Email de Contacto'),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: contactoController,
                              decoration: const InputDecoration(labelText: 'Contacto Telefónico *'),
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(16),
                                TelefoneInputFormatter(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: pessoaContactoController,
                              decoration: const InputDecoration(labelText: 'Pessoa de Contacto / Cargo', hintText: 'Ex: Engª Ana Silva'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: moradaController,
                        decoration: const InputDecoration(labelText: 'Morada de Carga / Entrega', hintText: 'Rua, Código Postal, Cidade'),
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
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.isNotEmpty && contactoController.text.isNotEmpty) {
                      Navigator.pop(context);
                      if (clienteExistente == null) {
                        _inserirCliente(
                          nome: nomeController.text.trim(),
                          email: emailController.text.trim(),
                          contacto: contactoController.text.trim(),
                          nif: nifController.text.trim(),
                          pessoaContacto: pessoaContactoController.text.trim(),
                          morada: moradaController.text.trim(),
                          ativo: acessoAtivo,
                        );
                      } else {
                        _atualizarCliente(
                          id: clienteExistente['id'] as int,
                          nome: nomeController.text.trim(),
                          email: emailController.text.trim(),
                          contacto: contactoController.text.trim(),
                          nif: nifController.text.trim(),
                          pessoaContacto: pessoaContactoController.text.trim(),
                          morada: moradaController.text.trim(),
                          ativo: acessoAtivo,
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