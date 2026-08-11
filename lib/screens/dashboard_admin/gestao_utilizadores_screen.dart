import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/breakpoints.dart';
import '../../core/temas_cores.dart';
import '../../core/mensagens.dart';
import 'dialogos/dialogo_adicionar_funcionario.dart';
import 'dialogos/dialogo_editar_utilizador.dart';
import 'dialogos/dialogo_rejeitar_registo.dart';
import 'widgets/cartao_kpi.dart';
import 'widgets/linha_utilizador.dart';
import 'widgets/painel_detalhe_utilizador.dart';
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
      backgroundColor: TemasCores.fundoEcraFrio,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: paddingEcra(context),
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
                      borderRadius: BorderRadius.circular(14),
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
          _buildKpiCard('Administradores', '$_totalAdmins', Icons.shield_outlined, TemasCores.adminAcento),
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
    // `Wrap` em vez de `Row`: o botão "Adicionar Novo Utilizador" não encolhe,
    // e num `Row` isso empurrava o título para uma largura residual tão
    // estreita que cada palavra quebrava para a sua própria linha. Com
    // `Wrap`, quando não cabem lado a lado, o bloco de ações desce inteiro
    // para a linha seguinte.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        const Text(
          'Gestão de Utilizadores',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: _carregarUtilizadores,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar lista',
              color: TemasCores.adminAcento,
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _abrirDialogAdicionar,
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.adminAcento,
                foregroundColor: TemasCores.textoInverso,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              prefixIcon: const Icon(Icons.search, color: TemasCores.adminAcento, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
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
            initialValue: _filtroCargo,
            isExpanded: true,
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
              DropdownMenuItem(value: 'Tecnico', child: Text('Técnicos de Manutenção')),
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

    // As colunas (Expanded de largura relativa) não têm para onde encolher em
    // ecrã estreito — em vez de espremer o texto e os botões de ação até
    // ilegível, a tabela mantém uma largura mínima e fica dentro de scroll
    // horizontal.
    final tabela = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTableHeader(),
        const Divider(height: 1, thickness: 1),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _utilizadoresFiltrados.length,
          separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
          itemBuilder: (context, index) {
            final ut = _utilizadoresFiltrados[index];
            return LinhaUtilizador(
              utilizador: ut,
              posto: _postoPorOperador[ut.utilizadorId],
              aoAbrirDetalhe: () => _abrirPainelDetalhe(ut),
              aoAprovar: () => _aprovarRapido(ut),
              aoRejeitar: () => _rejeitarRegisto(ut),
              aoEditar: () => _abrirDialogEditar(ut),
              aoAlterarEstado: (novoEstado) => _alterarEstadoConta(ut, novoEstado),
            );
          },
        ),
      ],
    );

    return Column(
      children: [
        if (_erroCarregamento != null)
          EstadoErro.compacto(
            titulo: 'A lista pode estar desatualizada — falhou a última atualização.',
            detalhe: _erroCarregamento,
            aoRepetir: _carregarUtilizadores,
          ),
        context.ehCompacto
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 700, child: tabela),
              )
            : tabela,
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
              // Sem `Flexible`, um título mais comprido ("Estado da Conta")
              // estourava a coluna assim que a tabela ficasse com o mínimo de
              // largura (scroll horizontal em ecrã estreito).
              Flexible(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ativa ? TemasCores.textoPrimario : TemasCores.textoTerciario,
                    fontSize: 13,
                  ),
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


  // --- DIALOGS E PROCESSAMENTO DE DADOS ---

  /// Aprovar um pendente é dar-lhe o cargo de operador e ativar a conta.
  Future<void> _aprovarRapido(UtilizadorModel ut) async {
    await _atualizarUtilizador(ut.utilizadorId, ut.nomeUtilizador, 'Operador', 'Ativo');
  }

  Future<void> _rejeitarRegisto(UtilizadorModel ut) async {
    final confirmou = await DialogoRejeitarRegisto.mostrar(context, nome: ut.nomeUtilizador);
    if (!confirmou || !mounted) return;
    await _alterarEstadoConta(ut, EstadoConta.inativo);
  }

  Future<void> _abrirDialogEditar(UtilizadorModel ut) async {
    final edicao = await DialogoEditarUtilizador.mostrar(context, utilizador: ut);
    if (edicao == null || !mounted) return;
    await _atualizarUtilizador(
      ut.utilizadorId,
      edicao.nome,
      edicao.perfil,
      edicao.estadoConta,
    );
  }

  Future<void> _abrirDialogAdicionar() async {
    final mensagem = await DialogoAdicionarFuncionario.mostrar(
      context,
      repositorio: _utilizadoresRepo,
    );
    if (mensagem == null || !mounted) return;
    _mostrarMensagem(mensagem);
    _carregarUtilizadores();
  }

  void _abrirPainelDetalhe(UtilizadorModel ut) {
    PainelDetalheUtilizador.mostrar(
      context,
      utilizador: ut,
      posto: _postoPorOperador[ut.utilizadorId],
      repositorio: _utilizadoresRepo,
      aoEditar: () => _abrirDialogEditar(ut),
    );
  }
}
