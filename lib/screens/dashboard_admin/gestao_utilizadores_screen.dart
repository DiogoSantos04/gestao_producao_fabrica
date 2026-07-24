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

  // Ordenação por coluna
  String _colunaOrdenacao = 'nome_utilizador';
  bool _ordemAscendente = true;

  // Mapa operador_id -> posto de trabalho atribuído (para chip e painel de detalhe)
  Map<String, Map<String, dynamic>> _postoPorOperador = {};

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

      // Postos de trabalho (para mostrar a que posto está afeto cada operador)
      final postos = await _supabase
          .from('postos_trabalho')
          .select('id, nome_posto, estado, operador_id')
          .not('operador_id', 'is', null);

      final mapaPostos = <String, Map<String, dynamic>>{};
      for (final p in (postos as List)) {
        final opId = p['operador_id']?.toString();
        if (opId != null) mapaPostos[opId] = Map<String, dynamic>.from(p);
      }

      setState(() {
        _todosUtilizadores = data;
        _postoPorOperador = mapaPostos;
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

    final filtrados = _todosUtilizadores.where((ut) {
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

    // Ordenação
    filtrados.sort((a, b) {
      final va = (a[_colunaOrdenacao] ?? '').toString().toLowerCase();
      final vb = (b[_colunaOrdenacao] ?? '').toString().toLowerCase();
      final cmp = va.compareTo(vb);
      return _ordemAscendente ? cmp : -cmp;
    });

    setState(() => _utilizadoresFiltrados = filtrados);
  }

  void _ordenarPor(String coluna) {
    setState(() {
      if (_colunaOrdenacao == coluna) {
        _ordemAscendente = !_ordemAscendente;
      } else {
        _colunaOrdenacao = coluna;
        _ordemAscendente = true;
      }
    });
    _filtrarUtilizadores();
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

  /// Altera apenas o estado da conta (usado pelo toggle rápido)
  Future<void> _alterarEstadoConta(Map<String, dynamic> ut, String novoEstado) async {
    final uid = ut['utilizador_id'] as String;
    try {
      await _supabase.from('utilizadores').update({
        'estado_conta': novoEstado,
      }).eq('utilizador_id', uid);

      // Atualização otimista local (evita recarregar tudo)
      setState(() => ut['estado_conta'] = novoEstado);
      _filtrarUtilizadores();
      _mostrarMensagem('Estado alterado para "$novoEstado".');
    } catch (e) {
      _mostrarMensagem('Erro ao alterar estado: $e', eErro: true);
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

  // --- CÁLCULO DE MÉTRICAS PARA OS CARTÕES DE RESUMO ---

  int get _totalUtilizadores => _todosUtilizadores.length;

  int get _totalAtivos => _todosUtilizadores.where((ut) {
        return (ut['estado_conta'] ?? '').toString().toLowerCase() == 'ativo';
      }).length;

  int get _totalPendentes => _todosUtilizadores.where((ut) {
        return (ut['estado_conta'] ?? '').toString().toLowerCase() == 'pendente';
      }).length;

  int get _totalAdmins => _todosUtilizadores.where((ut) {
        final p = (ut['perfil'] ?? '').toString().toLowerCase();
        return p == 'admin' || p == 'administrador';
      }).length;

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- CARTÕES DE RESUMO (KPIs) ---
                  _buildBarraResumo(),
                  const SizedBox(height: 24),

                  // --- CARTÃO PRINCIPAL COM TABELA ---
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
                          _buildHeader(),
                          const SizedBox(height: 24),
                          _buildBarraPesquisa(),
                          const SizedBox(height: 12),
                          Text(
                            'A mostrar ${_utilizadoresFiltrados.length} de $_totalUtilizadores utilizadores',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          _buildTabela(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildBarraResumo() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _buildKpiCard('Total de Utilizadores', '$_totalUtilizadores', Icons.people_outline, Colors.indigo),
          _buildKpiCard('Contas Ativas', '$_totalAtivos', Icons.check_circle_outline, Colors.green),
          _buildKpiCard('Pendentes de Aprovação', '$_totalPendentes', Icons.hourglass_empty, Colors.orange),
          _buildKpiCard('Administradores', '$_totalAdmins', Icons.shield_outlined, Colors.deepPurple),
        ];

        // Responsivo: 4 numa linha em ecrãs largos, 2 em médios, 1 em pequenos
        final bool largo = constraints.maxWidth > 900;
        final bool medio = constraints.maxWidth > 560;
        final int colunas = largo ? 4 : (medio ? 2 : 1);
        final double largura = (constraints.maxWidth - (colunas - 1) * 16) / colunas;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: cards.map((c) => SizedBox(width: largura, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildKpiCard(String titulo, String valor, IconData icone, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cor)),
                const SizedBox(height: 2),
                Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Text(
            'Gestão de Utilizadores',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
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
    );
  }

  Widget _buildBarraPesquisa() {
    return Row(
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
    );
  }

  Widget _buildTabela() {
    if (_utilizadoresFiltrados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('Nenhum utilizador encontrado.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      children: [
        _buildTableHeader(),
        const Divider(height: 1, thickness: 1),
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
    );
  }

  // --- AUXILIARES DE RENDERIZAÇÃO DA TABELA ---

  Widget _buildColunaOrdenavel(String titulo, String coluna, int flex, {Alignment alinhamento = Alignment.centerLeft}) {
    final bool ativa = _colunaOrdenacao == coluna;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _ordenarPor(coluna),
        child: Align(
          alignment: alinhamento,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: ativa ? Colors.black87 : Colors.grey,
                  fontSize: 13,
                ),
              ),
              if (ativa)
                Icon(
                  _ordemAscendente ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: Colors.black87,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          _buildColunaOrdenavel('Nome do Funcionário', 'nome_utilizador', 3),
          _buildColunaOrdenavel('Email', 'email', 4),
          _buildColunaOrdenavel('Perfil', 'perfil', 2),
          _buildColunaOrdenavel('Estado da Conta', 'estado_conta', 2),
          const Expanded(
            flex: 3,
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
    final String nome = (ut['nome_utilizador'] ?? 'N/A').toString();
    final String perfil = (ut['perfil'] ?? 'Operador').toString();
    final String estado = (ut['estado_conta'] ?? 'Ativo').toString();
    final String eLower = estado.toLowerCase();
    final bool ePendente = eLower == 'pendente';
    final bool eAtivo = eLower == 'ativo';

    final String uid = ut['utilizador_id'].toString();
    final Map<String, dynamic>? posto = _postoPorOperador[uid];
    final String pLower = perfil.toLowerCase();
    final bool eOperador = pLower == 'operador' || pLower == 'funcionario' || pLower == 'funcionário';

    return InkWell(
      onTap: () => _abrirPainelDetalhe(ut),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
        children: [
          // Nome do Funcionário (com avatar de iniciais + posto)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _buildAvatar(nome),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (eOperador) _buildChipPosto(posto),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Email
          Expanded(
            flex: 4,
            child: Text(
              ut['email'] ?? 'N/A',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Perfil (Badge)
          Expanded(
            flex: 2,
            child: Row(children: [_buildPerfilBadge(perfil)]),
          ),
          // Estado da Conta (Badge)
          Expanded(
            flex: 2,
            child: Row(children: [_buildEstadoBadge(estado)]),
          ),
          // Ações
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fluxo de pendentes: aprovar / rejeitar
                  if (ePendente) ...[
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      tooltip: 'Aprovar Registo',
                      onPressed: () => _aprovarRapido(ut),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 20),
                      tooltip: 'Rejeitar Registo',
                      onPressed: () => _rejeitarRegisto(ut),
                    ),
                  ] else
                    // Toggle rápido Ativo/Inativo (não aplicável a pendentes)
                    Tooltip(
                      message: eAtivo ? 'Desativar conta' : 'Ativar conta',
                      child: Switch(
                        value: eAtivo,
                        activeColor: Colors.green,
                        onChanged: (ligar) => _alterarEstadoConta(ut, ligar ? 'Ativo' : 'Inativo'),
                      ),
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
      ),
    );
  }

  /// Chip pequeno com o posto de trabalho atribuído ao operador (ou "Sem posto")
  Widget _buildChipPosto(Map<String, dynamic>? posto) {
    final bool temPosto = posto != null && (posto['nome_posto']?.toString().trim().isNotEmpty ?? false);
    final String label = temPosto ? posto['nome_posto'].toString() : 'Sem posto';
    final Color cor = temPosto ? Colors.teal : Colors.grey;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(temPosto ? Icons.precision_manufacturing_outlined : Icons.location_off_outlined, size: 12, color: cor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+'));
    String iniciais;
    if (partes.isEmpty || partes.first.isEmpty) {
      iniciais = '?';
    } else if (partes.length == 1) {
      iniciais = partes.first.substring(0, 1).toUpperCase();
    } else {
      iniciais = (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
    }

    // Cor determinística a partir do nome
    final cores = [
      Colors.indigo, Colors.teal, Colors.deepOrange, Colors.purple,
      Colors.blue, Colors.green, Colors.red, Colors.brown,
    ];
    final cor = cores[nome.hashCode.abs() % cores.length];

    return CircleAvatar(
      radius: 16,
      backgroundColor: cor.withOpacity(0.15),
      child: Text(
        iniciais,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  // --- ESTILIZAÇÃO DOS BADGES ---

  Widget _buildPerfilBadge(String perfil) {
    final pLower = perfil.toLowerCase();
    final bool eAdmin = pLower == 'admin' || pLower == 'administrador';
    final bool eCliente = pLower == 'cliente';

    Color fundo = const Color(0xFFEAEAEA);
    Color texto = Colors.black87;
    String label = 'Funcionário';

    if (eAdmin) {
      fundo = const Color(0xFF111625);
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

    Color fundo = const Color(0xFF707070);
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

  Future<void> _rejeitarRegisto(Map<String, dynamic> ut) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejeitar Registo'),
        content: Text(
          'Tem a certeza de que pretende rejeitar o registo de "${ut['nome_utilizador']}"?\n\n'
          'A conta ficará marcada como "Inativo" e o utilizador não poderá aceder à aplicação.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _alterarEstadoConta(ut, 'Inativo');
    }
  }

  // --- PAINEL DE DETALHE DO UTILIZADOR (visão 360º) ---

  /// Recolhe métricas do colaborador a partir das tabelas relacionadas
  Future<Map<String, dynamic>> _carregarMetricasUtilizador(String uid) async {
    // Fases concluídas por este utilizador (produção)
    final historico = await _supabase
        .from('historico_producao')
        .select('data_conclusao')
        .eq('utilizador_id', uid)
        .order('data_conclusao', ascending: false);

    // Incidências onde entrou como técnico de manutenção
    final incidencias = await _supabase
        .from('incidencias')
        .select('id')
        .eq('tecnico_id', uid);

    final listaHist = List<Map<String, dynamic>>.from(historico as List? ?? []);
    final listaInc = List<Map<String, dynamic>>.from(incidencias as List? ?? []);

    return {
      'fasesConcluidas': listaHist.length,
      'ultimaAtividade': listaHist.isNotEmpty ? listaHist.first['data_conclusao'] : null,
      'incidencias': listaInc.length,
    };
  }

  String _formatarData(dynamic valor) {
    if (valor == null) return 'Sem registo';
    try {
      final dt = DateTime.parse(valor.toString()).toLocal();
      String dois(int n) => n.toString().padLeft(2, '0');
      return '${dois(dt.day)}/${dois(dt.month)}/${dt.year} ${dois(dt.hour)}:${dois(dt.minute)}';
    } catch (_) {
      return valor.toString();
    }
  }

  void _abrirPainelDetalhe(Map<String, dynamic> ut) {
    final String uid = ut['utilizador_id'].toString();
    final String nome = (ut['nome_utilizador'] ?? 'N/A').toString();
    final String perfil = (ut['perfil'] ?? 'Operador').toString();
    final String estado = (ut['estado_conta'] ?? 'Ativo').toString();
    final Map<String, dynamic>? posto = _postoPorOperador[uid];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.white,
            child: SizedBox(
              width: 420,
              height: double.infinity,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabeçalho do painel
                      Row(
                        children: [
                          _buildAvatar(nome),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text(ut['email'] ?? 'N/A', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildPerfilBadge(perfil),
                          const SizedBox(width: 8),
                          _buildEstadoBadge(estado),
                        ],
                      ),
                      const Divider(height: 32),

                      // Posto atribuído
                      _buildLinhaDetalhe(
                        Icons.precision_manufacturing_outlined,
                        'Posto atribuído',
                        posto != null && (posto['nome_posto']?.toString().isNotEmpty ?? false)
                            ? '${posto['nome_posto']}  (${posto['estado'] ?? 'N/D'})'
                            : 'Nenhum posto atribuído',
                        Colors.teal,
                      ),

                      // Métricas carregadas de forma assíncrona
                      Expanded(
                        child: FutureBuilder<Map<String, dynamic>>(
                          future: _carregarMetricasUtilizador(uid),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 40),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            if (snapshot.hasError) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Text('Erro ao carregar métricas: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.red)),
                              );
                            }
                            final m = snapshot.data ?? {};
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLinhaDetalhe(
                                  Icons.check_circle_outline,
                                  'Fases de produção concluídas',
                                  '${m['fasesConcluidas'] ?? 0}',
                                  Colors.green,
                                ),
                                _buildLinhaDetalhe(
                                  Icons.schedule,
                                  'Última atividade',
                                  _formatarData(m['ultimaAtividade']),
                                  Colors.indigo,
                                ),
                                _buildLinhaDetalhe(
                                  Icons.build_outlined,
                                  'Intervenções como técnico',
                                  '${m['incidencias'] ?? 0}',
                                  Colors.deepOrange,
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      // Ação de edição a partir do painel
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _abrirDialogEditar(ut);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar Utilizador'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final offset = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  Widget _buildLinhaDetalhe(IconData icone, String titulo, String valor, Color cor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDialogEditar(Map<String, dynamic> ut) {
    final nomeController = TextEditingController(text: ut['nome_utilizador']);
    final emailController = TextEditingController(text: ut['email']);

    String perfilSelecionado = ut['perfil'] ?? 'Operador';
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
