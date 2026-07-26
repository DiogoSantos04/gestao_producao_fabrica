import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/temas_cores.dart';
import '../../models/cliente_model.dart';
import '../../models/encomenda_model.dart';
import '../../models/pedido_model.dart';
import '../../repositories/clientes_repository.dart';

/// Formata o número à medida que é escrito, usando a mesma regra que o
/// `ClienteModel` aplica ao apresentá-lo. Antes existiam duas implementações
/// independentes da mesma formatação.
class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final limpo = newValue.text.replaceAll(RegExp(r'[^\d+]'), '');
    final resultado = ClienteModel.formatarTelefone(limpo);
    return TextEditingValue(
      text: resultado,
      selection: TextSelection.collapsed(offset: resultado.length),
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

  List<ClienteModel> _clientes = [];
  bool _isLoading = true;

  // 🔍 CONTROLADORES E ESTADOS DE FILTRAGEM
  final TextEditingController _searchController = TextEditingController();
  String _pesquisaQuery = '';
  String _filtroEstado = 'Todos'; // 'Todos', 'Ativos', 'Inativos', 'Com Encomendas'

  // 🗂️ PAINEL LATERAL (DRAWER DETALHES DO CLIENTE)
  ClienteModel? _clienteDetalhesSelecionado;

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

  // --- GETTER QUE DEVOLVE OS CLIENTES FILTRADOS EM TEMPO REAL ---
  //
  // Os quatro helpers defensivos que existiam aqui (_obterTotalEncomendas,
  // _temEncomendas, _obterListaEncomendas, _obterListaPedidos) desapareceram:
  // desembrulhavam à mão as junções vindas do Supabase, trabalho que passou
  // para as fábricas dos modelos.

  List<ClienteModel> get _clientesFiltrados {
    return _clientes.where((cliente) {
      if (!cliente.corresponde(_pesquisaQuery)) return false;

      switch (_filtroEstado) {
        case 'Ativos':
          return cliente.ativo;
        case 'Inativos':
          return !cliente.ativo;
        case 'Com Encomendas':
          return cliente.temEncomendas;
        default:
          return true;
      }
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

          // Mantém o painel de detalhe sincronizado com os dados recarregados.
          final selecionado = _clienteDetalhesSelecionado;
          if (selecionado != null) {
            for (final c in _clientes) {
              if (c.id == selecionado.id) {
                _clienteDetalhesSelecionado = c;
                break;
              }
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

  // A formatação do telefone passou para `ClienteModel.contactoFormatado` /
  // `ClienteModel.formatarTelefone`, partilhada com o TelefoneInputFormatter.

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
    final int ativosPortal = _clientes.where((c) => c.ativo).length;
    final int comEncomendas = _clientes.where((c) => c.temEncomendas).length;
    final int totalEncomendas = _clientes.fold<int>(0, (sum, c) => sum + c.totalEncomendas);

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

  // --- COLUNAS DA LINHA DE CLIENTE ---
  // Extraídas de um único método de 191 linhas, para que cada coluna possa ser
  // lida e alterada isoladamente.

  /// Coluna 1: nome da empresa, NIF, email e morada.
  Widget _buildColunaIdentificacao(ClienteModel cliente) {
    final nif = cliente.nif ?? '';
    final morada = cliente.morada ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cliente.nomeCliente.isNotEmpty ? cliente.nomeCliente : 'N/A',
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
                cliente.email ?? 'Sem email',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (morada.isNotEmpty) ...[
          const SizedBox(height: 3),
          _buildLinhaIcone(Icons.location_on_outlined, morada, tamanho: 11),
        ],
      ],
    );
  }

  /// Coluna 2: telefone e interlocutor.
  Widget _buildColunaContacto(ClienteModel cliente) {
    final pessoa = cliente.pessoaContacto ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              cliente.contactoFormatado,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (pessoa.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildLinhaIcone(Icons.person_outline_rounded, pessoa, tamanho: 12, peso: FontWeight.w500),
        ],
      ],
    );
  }

  /// Coluna 3: total de encomendas, com atalho para o painel de detalhe.
  Widget _buildColunaHistorico(ClienteModel cliente) {
    return Row(
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
                  '${cliente.totalEncomendas} encomendas',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Coluna 4: estado do acesso ao portal de rastreio.
  Widget _buildColunaAcessoPortal(ClienteModel cliente) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: cliente.ativo ? const Color(0xFF707070) : const Color(0xFFEAEAEA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            cliente.ativo ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: cliente.ativo ? Colors.white : Colors.black54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  /// Coluna 5: ação de edição.
  Widget _buildColunaAcoes(ClienteModel cliente) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: () => _abrirDialogCliente(clienteExistente: cliente),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.black87),
        label: const Text('Editar Dados',
            style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }

  /// Linha compacta de ícone + texto, repetida nas colunas de identificação e contacto.
  Widget _buildLinhaIcone(IconData icone, String texto,
      {double tamanho = 12, FontWeight peso = FontWeight.normal}) {
    return Row(
      children: [
        Icon(icone, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(color: Colors.grey.shade500, fontSize: tamanho, fontWeight: peso),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildClienteRow(ClienteModel cliente) {
    return InkWell(
      onTap: () => setState(() => _clienteDetalhesSelecionado = cliente),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 3, child: _buildColunaIdentificacao(cliente)),
            Expanded(flex: 3, child: _buildColunaContacto(cliente)),
            Expanded(flex: 2, child: _buildColunaHistorico(cliente)),
            Expanded(flex: 2, child: _buildColunaAcessoPortal(cliente)),
            Expanded(flex: 2, child: _buildColunaAcoes(cliente)),
          ],
        ),
      ),
    );
  }

  // --- 🗂️ DRAWER LATERAL: PAINEL DE DETALHES DO CLIENTE ---

  Widget _buildDrawerDetalhesCliente() {
    final cliente = _clienteDetalhesSelecionado;
    if (cliente == null) return const SizedBox.shrink();

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
          _buildDrawerCabecalho(cliente),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDrawerSeccaoFiscal(cliente),
                  const SizedBox(height: 28),
                  _buildDrawerSeccaoPedidos(cliente.pedidos),
                  const SizedBox(height: 28),
                  _buildDrawerSeccaoEncomendas(cliente.encomendas),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cabeçalho escuro com nome, NIF e estado do portal.
  Widget _buildDrawerCabecalho(ClienteModel cliente) {
    final nif = cliente.nif ?? '';

    return Container(
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
                  cliente.nomeCliente.isNotEmpty ? cliente.nomeCliente : 'Cliente',
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
                  child: Text('NIF: $nif',
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cliente.ativo ? Colors.green.shade800 : Colors.red.shade800,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cliente.ativo ? 'Portal Ativo' : 'Portal Bloqueado',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dados cadastrais, fiscais e logísticos.
  Widget _buildDrawerSeccaoFiscal(ClienteModel cliente) {
    final nif = cliente.nif ?? '';
    final email = cliente.email ?? '';
    final pessoa = cliente.pessoaContacto ?? '';
    final morada = cliente.morada ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informações Fiscais e Logísticas',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
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
              _buildLinhaDetalhe(
                  Icons.email_outlined, 'Email', email.isNotEmpty ? email : 'Não registado'),
              const Divider(height: 16),
              _buildLinhaDetalhe(Icons.phone_outlined, 'Telefone', cliente.contactoFormatado),
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
      ],
    );
  }

  /// Pedidos submetidos pelo portal B2B.
  Widget _buildDrawerSeccaoPedidos(List<PedidoModel> pedidos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDrawerTituloSeccao(
          'Pedidos da Aplicação B2B',
          pedidos.length,
          fundoContador: Colors.blue.shade50,
          corContador: Colors.blue.shade800,
        ),
        const SizedBox(height: 12),
        if (pedidos.isEmpty)
          _buildDrawerVazio('Nenhum pedido submetido na app.')
        else
          Column(
            children: pedidos.map((p) {
              return _buildDrawerItem(
                titulo: p.nomeProduto ?? 'Produto',
                subtitulo: 'Qtd: ${p.quantidade} unidades',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration:
                      BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text(p.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  /// Ordens de produção já lançadas para o cliente.
  Widget _buildDrawerSeccaoEncomendas(List<EncomendaModel> encomendas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDrawerTituloSeccao(
          'Ordens de Produção Lançadas',
          encomendas.length,
          fundoContador: Colors.grey.shade100,
          corContador: Colors.grey.shade800,
        ),
        const SizedBox(height: 12),
        if (encomendas.isEmpty)
          _buildDrawerVazio('Nenhuma ordem de produção associada.')
        else
          Column(
            children: encomendas.map((e) {
              return _buildDrawerItem(
                titulo: e.codigoRastreio ?? 'TRC-N/A',
                subtitulo: '${e.nomeProduto ?? 'Produto'} • Qtd: ${e.quantidade}',
                trailing: Text(
                  e.dataEntregaIso ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildDrawerTituloSeccao(
    String titulo,
    int contador, {
    required Color fundoContador,
    required Color corContador,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: fundoContador, borderRadius: BorderRadius.circular(10)),
          child: Text('$contador',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corContador)),
        ),
      ],
    );
  }

  Widget _buildDrawerVazio(String mensagem) {
    return Text(mensagem,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic));
  }

  /// Cartão de item usado tanto pelos pedidos como pelas encomendas.
  /// Antes existiam duas construções praticamente idênticas.
  Widget _buildDrawerItem({
    required String titulo,
    required String subtitulo,
    required Widget trailing,
  }) {
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
              Text(titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
              Text(subtitulo, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          trailing,
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

  void _abrirDialogCliente({ClienteModel? clienteExistente}) {
    final nomeController = TextEditingController(text: clienteExistente?.nomeCliente ?? '');
    final emailController = TextEditingController(text: clienteExistente?.email ?? '');
    final nifController = TextEditingController(text: clienteExistente?.nif ?? '');
    final pessoaContactoController =
        TextEditingController(text: clienteExistente?.pessoaContacto ?? '');
    final moradaController = TextEditingController(text: clienteExistente?.morada ?? '');

    final contactoController = TextEditingController(
      text: clienteExistente != null
          ? ClienteModel.formatarTelefone(clienteExistente.contacto ?? '')
          : '',
    );
    bool acessoAtivo = clienteExistente?.ativo ?? true;

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
                          id: clienteExistente.id,
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