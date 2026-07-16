import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class GestaoUtilizadoresScreen extends StatefulWidget {
  const GestaoUtilizadoresScreen({super.key});

  @override
  State<GestaoUtilizadoresScreen> createState() => _GestaoUtilizadoresScreenState();
}

class _GestaoUtilizadoresScreenState extends State<GestaoUtilizadoresScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<dynamic> _todosUtilizadores = [];
  List<dynamic> _utilizadoresFiltrados = [];
  bool _isLoading = true;

  String _filtroCargo = 'Todos os cargos';

  @override
  void initState() {
    super.initState();
    _carregarUtilizadores();
    _searchController.addListener(_filtrarUtilizadores);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- LIGAÇÃO À BASE DE DADOS (SUPABASE) ---

  /// Procura todos os utilizadores registados na tabela
  Future<void> _carregarUtilizadores() async {
    try {
      setState(() => _isLoading = true);
      
      final data = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil, estado_conta')
          .order('nome_utilizador');

      setState(() {
        _todosUtilizadores = data;
        _isLoading = false;
      });
      _filtrarUtilizadores();
    } catch (e) {
      _mostrarMensagem('Erro ao carregar utilizadores: $e', eErro: true);
      setState(() => _isLoading = false);
    }
  }

  /// Filtra a lista localmente conforme o texto pesquisado e o cargo selecionado
  void _filtrarUtilizadores() {
    final query = _searchController.text.trim().toLowerCase();
    
    setState(() {
      _utilizadoresFiltrados = _todosUtilizadores.where((ut) {
        final nome = (ut['nome_utilizador'] ?? '').toString().toLowerCase();
        final email = (ut['email'] ?? '').toString().toLowerCase();
        final perfil = (ut['perfil'] ?? '').toString().toLowerCase();

        // Filtro por texto (Nome ou Email)
        final bateCertoComPesquisa = nome.contains(query) || email.contains(query);

        // Filtro por Cargo / Perfil
        bool bateCertoComCargo = true;
        if (_filtroCargo != 'Todos os cargos') {
          final filtroNormalizado = _filtroCargo.toLowerCase();
          if (filtroNormalizado == 'administrador' || filtroNormalizado == 'admin') {
            bateCertoComCargo = perfil == 'admin' || perfil == 'administrador';
          } else if (filtroNormalizado == 'funcionário' || filtroNormalizado == 'operador') {
            bateCertoComCargo = perfil == 'operador' || perfil == 'funcionario' || perfil == 'funcionário';
          } else {
            bateCertoComCargo = perfil == filtroNormalizado;
          }
        }

        return bateCertoComPesquisa && bateCertoComCargo;
      }).toList();
    });
  }

  /// Atualiza o perfil e estado do utilizador diretamente no Supabase
  Future<void> _atualizarUtilizador(String uid, String novoNome, String novoEmail, String novoPerfil, String novoEstado) async {
    try {
      setState(() => _isLoading = true);
      
      await _supabase.from('utilizadores').update({
        'nome_utilizador': novoNome,
        'email': novoEmail,
        'perfil': novoPerfil,
        'estado_conta': novoEstado,
      }).eq('utilizador_id', uid);

      _mostrarMensagem('Utilizador atualizado com sucesso!');
      _carregarUtilizadores();
    } catch (e) {
      _mostrarMensagem('Erro ao atualizar utilizador: $e', eErro: true);
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
                      // --- HEADER COM TÍTULO E BOTÃO ADICIONAR ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Gestão de Utilizadores',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          ElevatedButton.icon(
                            onPressed: _abrirDialogAdicionar,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Adicionar Novo Utilizador', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // --- BARRA DE PESQUISA E FILTRO ---
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Pesquisar por nome ou email...',
                                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: _filtroCargo,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: Colors.grey.shade300),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Todos os cargos', child: Text('Todos os cargos')),
                                DropdownMenuItem(value: 'Administrador', child: Text('Administradores')),
                                DropdownMenuItem(value: 'Operador', child: Text('Funcionários / Operadores')),
                                DropdownMenuItem(value: 'Cliente', child: Text('Clientes')),
                                DropdownMenuItem(value: 'Pendente', child: Text('Pendentes')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _filtroCargo = val);
                                  _filtrarUtilizadores();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // --- TABELA DE UTILIZADORES ---
                      _utilizadoresFiltrados.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text('Nenhum utilizador encontrado.', style: TextStyle(color: Colors.grey)),
                              ),
                            )
                          : Column(
                              children: [
                                // Cabeçalhos da Tabela
                                _buildTableHeader(),
                                const Divider(height: 1, thickness: 1),
                                // Linhas de utilizadores
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _utilizadoresFiltrados.length,
                                  separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                                  itemBuilder: (context, index) {
                                    return _buildUserRow(_utilizadoresFiltrados[index]);
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

  // --- AUXILIARES DE RENDERIZAÇÃO DA TABELA ---

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: const [
          Expanded(
            flex: 3,
            child: Text('Nome do Funcionário', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 4,
            child: Text('Email', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Perfil', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Estado da Conta', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
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

  Widget _buildUserRow(Map<String, dynamic> ut) {
    final String perfil = (ut['perfil'] ?? 'Operador').toString();
    final String estado = (ut['estado_conta'] ?? 'Ativo').toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          // Nome do Funcionário
          Expanded(
            flex: 3,
            child: Text(
              ut['nome_utilizador'] ?? 'N/A',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 14),
            ),
          ),
          // Email
          Expanded(
            flex: 4,
            child: Text(
              ut['email'] ?? 'N/A',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          // Perfil (Badge Estilizado)
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _buildPerfilBadge(perfil),
              ],
            ),
          ),
          // Estado da Conta (Badge Estilizado)
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _buildEstadoBadge(estado),
              ],
            ),
          ),
          // Ações
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botão de aprovação rápida se for pendente
                  if (estado.toLowerCase() == 'pendente')
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_outlined, color: Colors.green, size: 20),
                      tooltip: 'Aprovar Registo',
                      onPressed: () => _aprovarRapido(ut),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.black54, size: 20),
                    tooltip: 'Editar Utilizador',
                    onPressed: () => _abrirDialogEditar(ut),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ESTILIZAÇÃO DOS BADGES (IGUAL AO PRINT) ---

  Widget _buildPerfilBadge(String perfil) {
    final pLower = perfil.toLowerCase();
    final bool eAdmin = pLower == 'admin' || pLower == 'administrador';
    final bool eCliente = pLower == 'cliente';

    Color fundo = const Color(0xFFEAEAEA); // Cinzento claro por defeito (Funcionário)
    Color texto = Colors.black87;
    String label = 'Funcionário';

    if (eAdmin) {
      fundo = const Color(0xFF111625); // Preto/Escuro
      texto = Colors.white;
      label = 'Administrador';
    } else if (eCliente) {
      fundo = Colors.blue.shade50;
      texto = Colors.blue.shade800;
      label = 'Cliente';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: texto, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEstadoBadge(String estado) {
    final eLower = estado.toLowerCase();
    
    Color fundo = const Color(0xFF707070); // Cinzento médio para "Ativo"
    Color texto = Colors.white;

    if (eLower == 'inativo') {
      fundo = Colors.red.shade50;
      texto = Colors.red.shade700;
    } else if (eLower == 'pendente') {
      fundo = Colors.orange.shade50;
      texto = Colors.orange.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        estado,
        style: TextStyle(color: texto, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  // --- DIALOGS E PROCESSAMENTO DE DADOS ---

  Future<void> _aprovarRapido(Map<String, dynamic> ut) async {
    final uid = ut['utilizador_id'] as String;
    await _atualizarUtilizador(uid, ut['nome_utilizador'], ut['email'], 'Operador', 'Ativo');
  }

  void _abrirDialogEditar(Map<String, dynamic> ut) {
    final nomeController = TextEditingController(text: ut['nome_utilizador']);
    final emailController = TextEditingController(text: ut['email']);
    
    String perfilSelecionado = ut['perfil'] ?? 'Operador';
    // Garante que o valor bate certo com as opções do dropdown
    if (perfilSelecionado.toLowerCase() == 'admin') perfilSelecionado = 'Administrador';
    if (perfilSelecionado.toLowerCase() == 'funcionario') perfilSelecionado = 'Operador';

    String estadoSelecionado = ut['estado_conta'] ?? 'Ativo';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Utilizador'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeController,
                    decoration: const InputDecoration(labelText: 'Nome do Utilizador'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: perfilSelecionado,
                    decoration: const InputDecoration(labelText: 'Cargo / Perfil'),
                    items: const [
                      DropdownMenuItem(value: 'Administrador', child: Text('Administrador')),
                      DropdownMenuItem(value: 'Operador', child: Text('Funcionário (Operador)')),
                      DropdownMenuItem(value: 'Cliente', child: Text('Cliente Comercial')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => perfilSelecionado = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: estadoSelecionado,
                    decoration: const InputDecoration(labelText: 'Estado da Conta'),
                    items: const [
                      DropdownMenuItem(value: 'Ativo', child: Text('Ativo')),
                      DropdownMenuItem(value: 'Inativo', child: Text('Inativo')),
                      DropdownMenuItem(value: 'Pendente', child: Text('Pendente de Aprovação')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => estadoSelecionado = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    final uid = ut['utilizador_id'] as String;
                    Navigator.pop(context);
                    _atualizarUtilizador(
                      uid,
                      nomeController.text.trim(),
                      emailController.text.trim(),
                      perfilSelecionado == 'Administrador' ? 'Admin' : perfilSelecionado,
                      estadoSelecionado,
                    );
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

  void _abrirDialogAdicionar() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Adicionar Utilizador'),
          content: const Text(
            'Por questões de segurança e integridade das credenciais (encriptação Supabase Auth), os novos colaboradores devem registar a sua própria conta no ecrã de início da aplicação (através do botão "Solicitar Acesso").\n\nComo administrador, poderá aprovar e ativar o registo deles instantaneamente nesta lista assim que o fizerem.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Percebido'),
            ),
          ],
        );
      },
    );
  }
}