import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/iniciais.dart';
import '../../core/temas_cores.dart';
import '../../core/mensagens.dart';
import 'widgets/cartao_kpi.dart';
import 'widgets/etiqueta_estado.dart';
import '../../models/utilizador_model.dart';
import '../../repositories/postos_repository.dart';
import '../../repositories/utilizadores_repository.dart';
import '../../widgets/estado_erro.dart';

class GestaoUtilizadoresScreen extends StatefulWidget {
  const GestaoUtilizadoresScreen({super.key});

  @override
  State<GestaoUtilizadoresScreen> createState() => _GestaoUtilizadoresScreenState();
}

class _GestaoUtilizadoresScreenState extends State<GestaoUtilizadoresScreen> {
  final _utilizadoresRepo = UtilizadoresRepository();
  final _postosRepo = PostosRepository();
  final _searchController = TextEditingController();

  List<UtilizadorModel> _todosUtilizadores = [];
  List<UtilizadorModel> _utilizadoresFiltrados = [];
  bool _isLoading = true;

  /// Motivo da última falha a ler os utilizadores, ou `null` se correu bem.
  /// "Nenhum utilizador encontrado" numa tabela que nunca chegou a ser lida é
  /// uma afirmação falsa — e numa gestão de acessos é uma afirmação perigosa.
  String? _erroCarregamento;

  String _filtroCargo = 'Todos os cargos';

  // Ordenação por coluna
  String _colunaOrdenacao = 'nome_utilizador';
  bool _ordemAscendente = true;

  // Mapa operador_id -> posto de trabalho atribuído (para chip e painel de detalhe)
  Map<String, Map<String, dynamic>> _postoPorOperador = {};

  // Subscrição em tempo real aos postos, para manter os chips atualizados
  RealtimeChannel? _postosSub;
  // Atualização periódica (fallback que funciona mesmo sem Realtime replication)
  Timer? _timerPostos;

  @override
  void initState() {
    super.initState();
    _carregarUtilizadores();
    _searchController.addListener(_filtrarUtilizadores);
    _subscreverPostos();
    // Recarrega o mapa de postos a cada 10s para refletir alterações feitas noutros ecrãs
    _timerPostos = Timer.periodic(const Duration(seconds: 10), (_) => _recarregarPostos());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _timerPostos?.cancel();
    if (_postosSub != null) _postosRepo.client.removeChannel(_postosSub!);
    super.dispose();
  }

  /// Escuta alterações na tabela postos_trabalho e atualiza os chips sem recarregar tudo
  void _subscreverPostos() {
    _postosSub = _postosRepo.escutar('utilizadores-postos-changes', _recarregarPostos);
  }

  /// Recarrega apenas o mapa de postos (leve) e reaplica os filtros
  Future<void> _recarregarPostos() async {
    try {
      final mapaPostos = await _postosRepo.obterPorOperador();
      if (mounted) setState(() => _postoPorOperador = mapaPostos);
    } catch (e) {
      debugPrint('Erro ao recarregar postos: $e');
    }
  }

  // --- LIGAÇÃO À BASE DE DADOS (SUPABASE) ---

  /// Procura todos os utilizadores registados na tabela
  Future<void> _carregarUtilizadores() async {
    try {
      setState(() => _isLoading = true);

      final data = await _utilizadoresRepo.obterTodos();

      // Postos de trabalho (para mostrar a que posto está afeto cada operador)
      final mapaPostos = await _postosRepo.obterPorOperador();

      if (!mounted) return;
      setState(() {
        _todosUtilizadores = data;
        _postoPorOperador = mapaPostos;
        _isLoading = false;
        _erroCarregamento = null;
      });
      _filtrarUtilizadores();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _erroCarregamento = descreverErro(e);
      });
    }
  }

  /// Filtra a lista localmente conforme o texto pesquisado e o cargo selecionado
  void _filtrarUtilizadores() {
    final query = _searchController.text.trim().toLowerCase();

    final filtrados = _todosUtilizadores.where((ut) {
      final nome = ut.nomeUtilizador.toLowerCase();
      final email = (ut.email ?? '').toLowerCase();

      // Filtro por texto (Nome ou Email)
      final bateCertoComPesquisa = nome.contains(query) || email.contains(query);

      // Filtro por Cargo / Perfil. As variantes históricas do valor da coluna
      // ("Admin"/"Administrador", "Operador"/"Funcionario") já são normalizadas
      // pelo `PerfilUtilizador`, pelo que aqui basta comparar o enum.
      bool bateCertoComCargo = true;
      if (_filtroCargo != 'Todos os cargos') {
        bateCertoComCargo = ut.perfil == PerfilUtilizador.desdeTexto(_filtroCargo);
      }

      return bateCertoComPesquisa && bateCertoComCargo;
    }).toList();

    // Ordenação
    filtrados.sort((a, b) {
      final cmp = _valorOrdenacao(a).compareTo(_valorOrdenacao(b));
      return _ordemAscendente ? cmp : -cmp;
    });

    setState(() => _utilizadoresFiltrados = filtrados);
  }

  /// Valor de comparação para a coluna de ordenação ativa.
  ///
  /// Ordena-se pelo texto que a tabela mostra ao utilizador, não pelo valor
  /// gravado na coluna — para o perfil isso é a etiqueta ("Administrador",
  /// "Funcionário", "Cliente"), a mesma ordem que a versão anterior produzia
  /// para os valores que existem na base de dados.
  String _valorOrdenacao(UtilizadorModel ut) {
    return switch (_colunaOrdenacao) {
      'email' => (ut.email ?? '').toLowerCase(),
      'perfil' => ut.perfil.etiqueta.toLowerCase(),
      'estado_conta' => ut.estadoConta.valorBd.toLowerCase(),
      _ => ut.nomeUtilizador.toLowerCase(),
    };
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

  /// Atualiza o perfil e estado do utilizador diretamente no Supabase.
  /// O email não é alterado aqui — é a credencial gerida pelo Auth.
  Future<void> _atualizarUtilizador(String uid, String novoNome, String novoPerfil, String novoEstado) async {
    try {
      setState(() => _isLoading = true);

      await _utilizadoresRepo.atualizar(
        utilizadorId: uid,
        nome: novoNome,
        perfil: novoPerfil,
        estadoConta: novoEstado,
      );

      _mostrarMensagem('Utilizador atualizado com sucesso!');
      _carregarUtilizadores();
    } catch (e) {
      _mostrarMensagem('Erro ao atualizar utilizador: $e', eErro: true);
      setState(() => _isLoading = false);
    }
  }

  /// Altera apenas o estado da conta (usado pelo toggle rápido)
  Future<void> _alterarEstadoConta(UtilizadorModel ut, EstadoConta novoEstado) async {
    try {
      await _utilizadoresRepo.alterarEstadoConta(
        utilizadorId: ut.utilizadorId,
        estadoConta: novoEstado.valorBd,
      );

      // Atualização otimista local (evita recarregar tudo). O modelo é imutável,
      // pelo que se substitui a instância na lista em vez de mutar o registo.
      setState(() {
        final i = _todosUtilizadores.indexWhere((u) => u.utilizadorId == ut.utilizadorId);
        if (i != -1) _todosUtilizadores[i] = ut.copyWith(estadoConta: novoEstado);
      });
      _filtrarUtilizadores();
      _mostrarMensagem('Estado alterado para "${novoEstado.valorBd}".');
    } catch (e) {
      _mostrarMensagem('Erro ao alterar estado: $e', eErro: true);
    }
  }

  void _mostrarMensagem(String msg, {bool eErro = false}) {
    if (mounted) {
      context.mostrarMensagem(msg, eErro: eErro);
    }
  }

  // --- CÁLCULO DE MÉTRICAS PARA OS CARTÕES DE RESUMO ---

  int get _totalUtilizadores => _todosUtilizadores.length;

  int get _totalAtivos =>
      _todosUtilizadores.where((ut) => ut.estadoConta == EstadoConta.ativo).length;

  int get _totalPendentes =>
      _todosUtilizadores.where((ut) => ut.estadoConta == EstadoConta.pendente).length;

  int get _totalAdmins =>
      _todosUtilizadores.where((ut) => ut.perfil == PerfilUtilizador.administrador).length;

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
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
                    color: TemasCores.superficie,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: TemasCores.borda),
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
                            style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio),
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
          _buildKpiCard('Total de Utilizadores', '$_totalUtilizadores', Icons.people_outline, TemasCores.acentoIndigo),
          _buildKpiCard('Contas Ativas', '$_totalAtivos', Icons.check_circle_outline, TemasCores.sucesso),
          _buildKpiCard('Pendentes de Aprovação', '$_totalPendentes', Icons.hourglass_empty, TemasCores.alerta),
          _buildKpiCard('Administradores', '$_totalAdmins', Icons.shield_outlined, TemasCores.acentoRoxo),
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
    return ItemKpiCompacto(
      estilo: EstiloKpi.utilizadores,
      titulo: titulo,
      valor: valor,
      icone: icone,
      cor: cor,
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Flexible(
          child: Text(
            'Gestão de Utilizadores',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _carregarUtilizadores,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar lista',
              color: TemasCores.textoSecundario,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _abrirDialogAdicionar,
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.acaoPrincipal,
                foregroundColor: TemasCores.textoInverso,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Novo Utilizador', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
              prefixIcon: const Icon(Icons.search, color: TemasCores.textoTerciario, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: TemasCores.bordaForte),
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
                borderSide: const BorderSide(color: TemasCores.bordaForte),
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
    // A falha vem antes da lista vazia: sem esta distinção, não conseguir ler a
    // tabela era indistinguível de não haver utilizadores.
    if (_erroCarregamento != null && _todosUtilizadores.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: EstadoErro(
          titulo: 'Não foi possível carregar os utilizadores',
          detalhe: _erroCarregamento,
          aoRepetir: _carregarUtilizadores,
        ),
      );
    }

    if (_utilizadoresFiltrados.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('Nenhum utilizador encontrado.', style: TextStyle(color: TemasCores.textoTerciario)),
        ),
      );
    }

    return Column(
      children: [
        if (_erroCarregamento != null)
          EstadoErro.compacto(
            titulo: 'A lista pode estar desatualizada — falhou a última atualização.',
            detalhe: _erroCarregamento,
            aoRepetir: _carregarUtilizadores,
          ),
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
                  color: ativa ? TemasCores.textoPrimario : TemasCores.textoTerciario,
                  fontSize: 13,
                ),
              ),
              if (ativa)
                Icon(
                  _ordemAscendente ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: TemasCores.textoPrimario,
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
              child: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserRow(UtilizadorModel ut) {
    final String nome = ut.nomeUtilizador.isEmpty ? 'N/A' : ut.nomeUtilizador;
    final bool ePendente = ut.estadoConta == EstadoConta.pendente;
    final bool eAtivo = ut.estadoConta == EstadoConta.ativo;

    final Map<String, dynamic>? posto = _postoPorOperador[ut.utilizadorId];
    final bool eOperador = ut.perfil == PerfilUtilizador.operador;

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
                        style: const TextStyle(fontWeight: FontWeight.w600, color: TemasCores.textoPrimario, fontSize: 14),
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
              ut.email ?? 'N/A',
              style: const TextStyle(color: TemasCores.textoApoio, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Perfil (Badge)
          Expanded(
            flex: 2,
            child: Row(children: [_buildPerfilBadge(ut.perfil)]),
          ),
          // Estado da Conta (Badge)
          Expanded(
            flex: 2,
            child: Row(children: [_buildEstadoBadge(ut.estadoConta)]),
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
                      icon: const Icon(Icons.check_circle_outline, color: TemasCores.sucesso, size: 20),
                      tooltip: 'Aprovar Registo',
                      onPressed: () => _aprovarRapido(ut),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: TemasCores.erro, size: 20),
                      tooltip: 'Rejeitar Registo',
                      onPressed: () => _rejeitarRegisto(ut),
                    ),
                  ] else
                    // Toggle rápido Ativo/Inativo (não aplicável a pendentes)
                    Tooltip(
                      message: eAtivo ? 'Desativar conta' : 'Ativar conta',
                      child: Switch(
                        value: eAtivo,
                        activeColor: TemasCores.sucesso,
                        onChanged: (ligar) => _alterarEstadoConta(
                          ut,
                          ligar ? EstadoConta.ativo : EstadoConta.inativo,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: TemasCores.textoSecundario, size: 20),
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
    final Color cor = temPosto ? TemasCores.acentoTurquesa : TemasCores.textoTerciario;

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
    final iniciais = obterIniciais(
      nome,
      omissao: '?',
      letrasNomeUnico: 1,
      usarUltimoNome: true,
    );
    final cor = corAvatar(nome);

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

  Widget _buildPerfilBadge(PerfilUtilizador perfil) {
    // Um perfil não reconhecido continua a apresentar-se como "Funcionário",
    // tal como antes (o `else` do encadeado original).
    final (Color fundo, Color texto) = switch (perfil) {
      PerfilUtilizador.administrador => (TemasCores.marcaEscura, TemasCores.textoInverso),
      PerfilUtilizador.cliente => (TemasCores.infoFundo, TemasCores.infoTextoForte),
      _ => (TemasCores.estadoInativoFundo, TemasCores.textoPrimario),
    };
    return EtiquetaEstado.pilula(rotulo: perfil.etiqueta, fundo: fundo, texto: texto);
  }

  Widget _buildEstadoBadge(EstadoConta estado) {
    final (Color fundo, Color texto) = switch (estado) {
      EstadoConta.inativo => (TemasCores.erroFundo, TemasCores.erroTexto),
      EstadoConta.pendente => (TemasCores.alertaFundo, TemasCores.alertaTexto),
      EstadoConta.ativo => (TemasCores.estadoAtivoFundo, TemasCores.textoInverso),
    };

    return EtiquetaEstado.pilula(rotulo: estado.valorBd, fundo: fundo, texto: texto);
  }

  // --- DIALOGS E PROCESSAMENTO DE DADOS ---

  Future<void> _aprovarRapido(UtilizadorModel ut) async {
    await _atualizarUtilizador(ut.utilizadorId, ut.nomeUtilizador, 'Operador', 'Ativo');
  }

  Future<void> _rejeitarRegisto(UtilizadorModel ut) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejeitar Registo'),
        content: Text(
          'Tem a certeza de que pretende rejeitar o registo de "${ut.nomeUtilizador}"?\n\n'
          'A conta ficará marcada como "Inativo" e o utilizador não poderá aceder à aplicação.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: TemasCores.erro, foregroundColor: TemasCores.textoInverso),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rejeitar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _alterarEstadoConta(ut, EstadoConta.inativo);
    }
  }

  // --- PAINEL DE DETALHE DO UTILIZADOR (visão 360º) ---

  /// Recolhe métricas do colaborador a partir das tabelas relacionadas
  Future<Map<String, dynamic>> _carregarMetricasUtilizador(String uid) {
    return _utilizadoresRepo.obterMetricas(uid);
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

  void _abrirPainelDetalhe(UtilizadorModel ut) {
    final String uid = ut.utilizadorId;
    final String nome = ut.nomeUtilizador.isEmpty ? 'N/A' : ut.nomeUtilizador;
    final Map<String, dynamic>? posto = _postoPorOperador[uid];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: TemasCores.veuModal,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: TemasCores.superficie,
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
                                Text(ut.email ?? 'N/A', style: const TextStyle(fontSize: 13, color: TemasCores.textoApoio)),
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
                          _buildPerfilBadge(ut.perfil),
                          const SizedBox(width: 8),
                          _buildEstadoBadge(ut.estadoConta),
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
                        TemasCores.acentoTurquesa,
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
                                    style: const TextStyle(color: TemasCores.erro)),
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
                                  TemasCores.sucesso,
                                ),
                                _buildLinhaDetalhe(
                                  Icons.schedule,
                                  'Última atividade',
                                  _formatarData(m['ultimaAtividade']),
                                  TemasCores.acentoIndigo,
                                ),
                                _buildLinhaDetalhe(
                                  Icons.build_outlined,
                                  'Intervenções como técnico',
                                  '${m['incidencias'] ?? 0}',
                                  TemasCores.acentoLaranjaEscuro,
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
                Text(titulo, style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio)),
                const SizedBox(height: 2),
                Text(valor, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: TemasCores.textoPrimario)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _abrirDialogEditar(UtilizadorModel ut) {
    final nomeController = TextEditingController(text: ut.nomeUtilizador);
    final emailController = TextEditingController(text: ut.email);

    // Os `value` do dropdown têm de coincidir exatamente com os seus
    // `DropdownMenuItem`, que usam 'Operador' e não a etiqueta 'Funcionário'.
    String perfilSelecionado = switch (ut.perfil) {
      PerfilUtilizador.administrador => 'Administrador',
      PerfilUtilizador.cliente => 'Cliente',
      _ => 'Operador',
    };

    String estadoSelecionado = ut.estadoConta.valorBd;

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
                  // O email de login vive no Supabase Auth e não pode ser alterado
                  // a partir daqui. Editá-lo só nesta tabela dessincronizava os dois
                  // e o utilizador deixava de conseguir entrar com o email que via.
                  TextField(
                    controller: emailController,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Email (credencial de acesso)',
                      helperText: 'Alterável apenas pelo próprio, no seu perfil.',
                      helperMaxLines: 2,
                    ),
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
                    Navigator.pop(context);
                    _atualizarUtilizador(
                      ut.utilizadorId,
                      nomeController.text.trim(),
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

  /// Cria a conta de um novo funcionário SEM afetar a sessão do admin.
  /// O isolamento do cliente Supabase é responsabilidade do repositório.
  Future<void> _criarFuncionario(String nome, String email, String password) async {
    await _utilizadoresRepo.criarFuncionario(
      nome: nome,
      email: email,
      password: password,
    );
    _mostrarMensagem('Funcionário "$nome" criado com sucesso!');
    _carregarUtilizadores();
  }

  void _abrirDialogAdicionar() {
    final nomeController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool aGravar = false;
    bool ocultarPassword = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar Novo Funcionário'),
              content: SizedBox(
                width: 400,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'A conta é criada de imediato como Operador (Ativo). '
                        'Entregue estas credenciais ao funcionário para ele iniciar sessão.',
                        style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nomeController,
                        enabled: !aGravar,
                        decoration: const InputDecoration(
                          labelText: 'Nome do Funcionário',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Indique o nome' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        enabled: !aGravar,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Indique o email';
                          if (!v.contains('@') || !v.contains('.')) return 'Email inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        enabled: !aGravar,
                        obscureText: ocultarPassword,
                        decoration: InputDecoration(
                          labelText: 'Palavra-passe inicial',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(ocultarPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setDialogState(() => ocultarPassword = !ocultarPassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 6) return 'Mínimo 6 caracteres';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: aGravar ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: aGravar
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => aGravar = true);
                          try {
                            await _criarFuncionario(
                              nomeController.text.trim(),
                              emailController.text.trim(),
                              passwordController.text.trim(),
                            );
                            if (context.mounted) Navigator.pop(context);
                          } catch (e) {
                            setDialogState(() => aGravar = false);
                            final msg = e.toString().replaceAll('Exception: ', '');
                            _mostrarMensagem('Erro ao criar funcionário: $msg', eErro: true);
                          }
                        },
                  child: aGravar
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
                        )
                      : const Text('Criar Funcionário'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
