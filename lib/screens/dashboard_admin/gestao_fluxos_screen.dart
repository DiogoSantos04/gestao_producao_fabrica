import 'package:flutter/material.dart';
import '../../core/breakpoints.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/fase_model.dart';
import '../../repositories/fluxos_repository.dart';
import '../../widgets/estado_erro.dart';

class GestaoFluxosScreen extends StatefulWidget {
  const GestaoFluxosScreen({super.key});

  @override
  State<GestaoFluxosScreen> createState() => _GestaoFluxosScreenState();
}

class _GestaoFluxosScreenState extends State<GestaoFluxosScreen> {
  final _fluxosRepo = FluxosRepository();

  List<Map<String, dynamic>> _tipologias = [];
  List<FaseModel> _fases = [];

  Map<String, dynamic>? _tipoProdutoSelecionado;
  bool _isLoadingTipologias = true;
  bool _isLoadingFases = false;

  /// As duas listas deste ecrã carregam de forma independente — a coluna das
  /// tipologias e o roteiro da tipologia escolhida — pelo que cada uma tem o
  /// seu estado de erro. Uma falha a ler o roteiro não deve apagar a coluna da
  /// esquerda, que continua boa.
  String? _erroTipologias;
  String? _erroFases;

  final ScrollController _scrollTipologias = ScrollController();

  // Catálogo oficial e padronizado de Postos de Trabalho da Fábrica
  final List<String> _postosTrabalhoDisponiveis = [
    'Posto de Corte (CNC)',
    'Posto de Lixagem',
    'Posto de Pintura / Lacagem',
    'Posto de Secagem',
    'Posto de Montagem',
    'Posto de Controlo de Qualidade',
    'Posto de Embalamento',
  ];

  @override
  void initState() {
    super.initState();
    _carregarTipologias();
  }

  @override
  void dispose() {
    _scrollTipologias.dispose();
    super.dispose();
  }

  // --- FUNÇÕES DA BASE DE DADOS (SUPABASE) ---

  Future<void> _carregarTipologias() async {
    try {
      setState(() => _isLoadingTipologias = true);
      final data = await _fluxosRepo.obterTipologias();

      if (!mounted) return;
      setState(() {
        _tipologias = data;
        _isLoadingTipologias = false;
        _erroTipologias = null;

        if (_tipologias.isNotEmpty && _tipoProdutoSelecionado == null) {
          _selecionarTipologia(_tipologias.first);
        }
      });
    } catch (e) {
      // O `_isLoadingTipologias` ficava a `true` para sempre neste caminho: a
      // coluna passava o resto da sessão com o indicador a rodar.
      if (!mounted) return;
      setState(() {
        _isLoadingTipologias = false;
        _erroTipologias = descreverErro(e);
      });
    }
  }

  Future<void> _carregarFases(int tipoProdutoId) async {
    try {
      setState(() => _isLoadingFases = true);

      final data = await _fluxosRepo.obterFases(tipoProdutoId);
      if (!mounted) return;

      setState(() {
        _fases = data;
        _isLoadingFases = false;
        _erroFases = null;
      });
    } catch (e) {
      // Mesmo problema do carregamento das tipologias: sem isto o painel do
      // roteiro ficava com o indicador a rodar indefinidamente.
      if (!mounted) return;
      setState(() {
        _isLoadingFases = false;
        _erroFases = descreverErro(e);
      });
    }
  }

  void _selecionarTipologia(Map<String, dynamic> tipo) {
    setState(() {
      _tipoProdutoSelecionado = tipo;
    });
    _carregarFases(tipo['id']);
  }

  Future<void> _criarTipologia(String nome) async {
    try {
      final response = await _fluxosRepo.criarTipologia(nome);

      await _carregarTipologias();
      _selecionarTipologia(response);
    } catch (e) {
      _mostrarErro('Erro ao criar tipologia: $e');
    }
  }

  /// 📋 FUNCIONALIDADE: Clona uma tipologia inteira com todo o seu roteiro de fases
  Future<void> _duplicarFluxo(String novoNome) async {
    if (_tipoProdutoSelecionado == null) return;

    try {
      // 1. Criar o novo registo na tabela tipos_produto
      final novoProduto = await _fluxosRepo.criarTipologia(novoNome);

      // 2. Copiar todas as fases do produto de origem para a nova tipologia
      await _fluxosRepo.duplicarFases(
        novoTipoProdutoId: novoProduto['id'] as int,
        fasesOrigem: _fases,
      );

      // 3. Atualizar a lista de tipologias e selecionar a nova
      await _carregarTipologias();
      _selecionarTipologia(novoProduto);

      if (mounted) {
        context.mostrarSnack(
          'Fluxo "$novoNome" duplicado com sucesso!',
          cor: TemasCores.sucessoTexto,
        );
      }
    } catch (e) {
      _mostrarErro('Erro ao duplicar fluxo produtivo: $e');
    }
  }

  Future<void> _eliminarTipologia(int id) async {
    try {
      await _fluxosRepo.eliminarTipologia(id);
      if (!mounted) return;
      setState(() {
        _tipoProdutoSelecionado = null;
        _fases = [];
      });
      _carregarTipologias();
    } catch (e) {
      _mostrarErro(
        'Erro ao eliminar tipologia. Verifique se existem encomendas associadas a este produto.',
      );
    }
  }

  Future<void> _salvarFase({
    int? id,
    required String nome,
    required String descricao,
    required String posto,
    required int tempo,
    required List<String> checklist,
    String nomePublico = '',
  }) async {
    try {
      if (_tipoProdutoSelecionado == null) {
        _mostrarErro('Nenhum produto selecionado.');
        return;
      }

      await _fluxosRepo.guardarFase(
        id: id,
        tipoProdutoId: _tipoProdutoSelecionado!['id'] as int,
        nome: nome,
        descricao: descricao,
        posto: posto,
        tempo: tempo,
        checklist: checklist,
        ordem: id == null ? (_fases.length + 1) : null,
        nomePublico: nomePublico,
      );

      await _carregarFases(_tipoProdutoSelecionado!['id']);
    } catch (e) {
      _mostrarErro('Erro ao guardar fase no Supabase: $e');
    }
  }

  Future<void> _eliminarFase(int id) async {
    try {
      await _fluxosRepo.eliminarFase(id);
      _carregarFases(_tipoProdutoSelecionado!['id']);
    } catch (e) {
      _mostrarErro('Erro ao eliminar fase. Tente novamente.');
    }
  }

  /// Move a fase de [oldIndex] para [newIndex] e persiste a nova ordenação.
  ///
  /// Ligado a `onReorderItem`, que já entrega [newIndex] descontado da remoção
  /// do item — ao contrário do `onReorder` obsoleto, que obrigava a corrigi-lo
  /// à mão.
  Future<void> _reordenarFases(int oldIndex, int newIndex) async {
    setState(() {
      final item = _fases.removeAt(oldIndex);
      _fases.insert(newIndex, item);
    });

    try {
      await _fluxosRepo.reordenarFases(_fases.map((f) => f.id).toList());
    } catch (e) {
      _mostrarErro('Erro ao guardar nova ordenação: $e');
    }
  }

  void _mostrarErro(String msg) {
    if (mounted) {
      context.mostrarMensagem(msg, eErro: true);
    }
  }

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 850;

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: Padding(
        padding: paddingEcra(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fluxos Produtivos',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: eDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildPainelEsquerdoTipologias(
                            alturaLimitada: true,
                          ),
                        ),
                        const VerticalDivider(width: 32, thickness: 1),
                        Expanded(flex: 2, child: _buildPainelDireitoFluxo()),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildPainelEsquerdoTipologias(),
                          const Divider(height: 32),
                          _buildPainelDireitoFluxo(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPainelEsquerdoTipologias({bool alturaLimitada = false}) {
    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tipologias de Produto',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Selecione uma tipologia para desenhar o fluxo',
              style: TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
            ),
            const SizedBox(height: 16),
            if (_erroTipologias != null && _tipologias.isEmpty)
              EstadoErro(
                titulo: 'Não foi possível carregar as tipologias',
                detalhe: _erroTipologias,
                aoRepetir: _carregarTipologias,
              )
            else if (_erroTipologias != null)
              EstadoErro.compacto(
                titulo: 'A lista de tipologias pode estar desatualizada.',
                detalhe: _erroTipologias,
                aoRepetir: _carregarTipologias,
              ),
            _envolverLista(
              alturaLimitada,
              _isLoadingTipologias
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: alturaLimitada ? _scrollTipologias : null,
                      padding: alturaLimitada
                          ? const EdgeInsets.only(right: 8)
                          : EdgeInsets.zero,
                      shrinkWrap: !alturaLimitada,
                      physics: alturaLimitada
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: _tipologias.length,
                      itemBuilder: (context, index) {
                        final tipo = _tipologias[index];
                        final bool eSelecionado =
                            _tipoProdutoSelecionado?['id'] == tipo['id'];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: eSelecionado
                                  ? TemasCores.adminAcento
                                  : TemasCores.borda,
                              width: eSelecionado ? 2 : 1,
                            ),
                            color: eSelecionado
                                ? TemasCores.adminAcentoFundo
                                : Colors.transparent,
                          ),
                          // `ListTile` pintava o fundo e o efeito de toque no
                          // `Material` mais próximo — que era o do `Card` lá
                          // fora, por trás deste `Container` colorido, tornando-os
                          // invisíveis. Precisa do seu próprio `Material`.
                          child: Material(
                            type: MaterialType.transparency,
                            borderRadius: BorderRadius.circular(9),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              title: Text(
                                tipo['nome_tipo_produto'] ?? '',
                                style: TextStyle(
                                  fontWeight: eSelecionado
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: eSelecionado
                                      ? TemasCores.adminAcentoForte
                                      : TemasCores.textoPrimario,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 14,
                                    color: TemasCores.textoTerciario,
                                  ),
                                  if (eSelecionado)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: TemasCores.erro,
                                        size: 18,
                                      ),
                                      onPressed: () =>
                                          _eliminarTipologia(tipo['id']),
                                    ),
                                ],
                              ),
                              onTap: () => _selecionarTipologia(tipo),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _abrirDialogNovaTipologia,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
                backgroundColor: TemasCores.adminAcento,
                foregroundColor: TemasCores.textoInverso,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova Tipologia'),
            ),
          ],
        ),
      ),
    );
  }

  /// Em desktop a altura do cartão é limitada: a lista fica com scroll próprio
  /// para o botão "Nova Tipologia" continuar visível sem overflow.
  Widget _envolverLista(bool alturaLimitada, Widget lista) {
    if (!alturaLimitada) return lista;
    if (_isLoadingTipologias) return Expanded(child: lista);
    return Expanded(
      child: Scrollbar(
        controller: _scrollTipologias,
        thumbVisibility: true,
        child: lista,
      ),
    );
  }

  Widget _buildPainelDireitoFluxo() {
    if (_tipoProdutoSelecionado == null) {
      return const Card(
        child: Center(
          child: Text('Crie ou selecione uma tipologia para ver o fluxo.'),
        ),
      );
    }

    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCabecalhoFluxo(),
            const SizedBox(height: 24),

            if (_fases.isNotEmpty) _buildBreadcrumbsFases(),

            const SizedBox(height: 24),

            _buildListaFases(),
          ],
        ),
      ),
    );
  }

  /// Cabeçalho do painel: nome da tipologia e ações de duplicar/adicionar.
  Widget _buildCabecalhoFluxo() {
    final titulo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Fluxo Produtivo: ${_tipoProdutoSelecionado!['nome_tipo_produto']}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Defina o circuito sequencial de produção das peças',
          style: TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
        ),
      ],
    );

    final botoes = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _abrirDialogDuplicarFluxo,
          style: OutlinedButton.styleFrom(
            foregroundColor: TemasCores.infoTexto,
            side: const BorderSide(color: TemasCores.infoClaro),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Duplicar Fluxo'),
        ),
        ElevatedButton.icon(
          onPressed: () => _abrirDialogFase(),
          style: ElevatedButton.styleFrom(
            backgroundColor: TemasCores.adminAcento,
            foregroundColor: TemasCores.textoInverso,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Adicionar Fase'),
        ),
      ],
    );

    // Título comprido + dois botões não cabem lado a lado em ecrã estreito —
    // este cabeçalho não tinha nenhuma adaptação própria, nem sequer no
    // layout "estreito" do ecrã (secção 5 do plano de responsividade).
    if (context.ehCompacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: 12), botoes],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: titulo),
        botoes,
      ],
    );
  }

  /// Lista reordenável das fases, ou os estados de carregamento/vazio.
  Widget _buildListaFases() {
    if (_isLoadingFases) {
      return const Center(child: CircularProgressIndicator());
    }
    // "Nenhuma fase definida" convida a desenhar o roteiro de raiz; se o que
    // falhou foi a leitura, o roteiro pode já existir e seria duplicado.
    if (_erroFases != null && _fases.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: EstadoErro(
          titulo: 'Não foi possível carregar as fases deste fluxo',
          detalhe: _erroFases,
          aoRepetir: () {
            final id = _tipoProdutoSelecionado?['id'];
            if (id != null) _carregarFases(id as int);
          },
        ),
      );
    }

    if (_fases.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            'Nenhuma fase definida para este fluxo.',
            style: TextStyle(color: TemasCores.textoTerciario),
          ),
        ),
      );
    }

    return SizedBox(
      height: 400,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: true,
        itemCount: _fases.length,
        onReorderItem: _reordenarFases,
        itemBuilder: (context, index) => _buildCartaoFase(_fases[index], index),
      ),
    );
  }

  /// Cartão de uma fase do roteiro.
  Widget _buildCartaoFase(FaseModel fase, int index) {
    final checklistItems = fase.checklist;

    return Card(
      key: ValueKey(fase.id),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: TemasCores.textoTerciario),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // O nome da fase não tinha `Flexible` — com o `Spacer` e
                  // os dois `Chip` a seguir, um nome comprido estourava a
                  // linha em ecrã estreito. `Wrap` deixa tudo cair para a
                  // linha seguinte em vez de forçar o cartão a alargar.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TemasCores.infoFundo,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Fase ${index + 1}',
                          style: const TextStyle(
                            color: TemasCores.infoTexto,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Text(
                        fase.nomeFasePadrao,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (fase.postoTrabalho != null &&
                          fase.postoTrabalho!.isNotEmpty)
                        Chip(
                          avatar: const Icon(
                            Icons.precision_manufacturing,
                            size: 12,
                          ),
                          label: Text(
                            fase.postoTrabalho!,
                            style: const TextStyle(fontSize: 10),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      Chip(
                        avatar: const Icon(Icons.timer_outlined, size: 12),
                        label: Text(
                          '${fase.tempoEstimado} min',
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  // Sem nome público, o cliente vê o nome
                  // técnico — não vale a pena repeti-lo.
                  if (fase.nomeParaCliente != fase.nomeFasePadrao) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          size: 12,
                          color: TemasCores.textoTerciario,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'O cliente vê: ${fase.nomeParaCliente}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: TemasCores.textoTerciario,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    fase.descricao ?? 'Sem descrição.',
                    style: const TextStyle(
                      color: TemasCores.textoApoio,
                      fontSize: 13,
                    ),
                  ),
                  if (checklistItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: checklistItems.map((item) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: TemasCores.sucessoFundo,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: TemasCores.sucessoBorda),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_box_outlined,
                                size: 11,
                                color: TemasCores.sucessoTexto,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: TemasCores.sucessoTextoForte,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(
                Icons.edit_outlined,
                color: TemasCores.textoTerciario,
                size: 20,
              ),
              onPressed: () => _abrirDialogFase(faseExistente: fase),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: TemasCores.erro,
                size: 20,
              ),
              onPressed: () => _eliminarFase(fase.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbsFases() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_fases.length, (index) {
          final f = _fases[index];
          final eUltimo = index == _fases.length - 1;

          return Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: TemasCores.marcaEscura,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Fase ${index + 1}: ${f.nomeFasePadrao}',
                  style: const TextStyle(
                    color: TemasCores.textoInverso,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!eUltimo)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.chevron_right,
                    color: TemasCores.textoTerciario,
                    size: 16,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  void _abrirDialogNovaTipologia() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nova Tipologia de Produto'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Nome da Tipologia (Ex: Cadeiras, Sofás)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  _criarTipologia(controller.text.trim());
                  Navigator.pop(context);
                }
              },
              child: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
  }

  void _abrirDialogDuplicarFluxo() {
    if (_tipoProdutoSelecionado == null) return;

    final nomeAtual = _tipoProdutoSelecionado!['nome_tipo_produto'] ?? '';
    final controller = TextEditingController(text: '$nomeAtual (Cópia)');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Duplicar Fluxo Produtivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Irá ser criada uma nova tipologia clonando todas as fases, postos e tempos do fluxo "$nomeAtual".',
                style: const TextStyle(
                  fontSize: 13,
                  color: TemasCores.textoPrimario,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Nome da Nova Tipologia *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.infoTexto,
                foregroundColor: TemasCores.textoInverso,
              ),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Duplicar'),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context);
                  _duplicarFluxo(controller.text.trim());
                } else {
                  _mostrarErro('O nome da nova tipologia é obrigatório.');
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _abrirDialogFase({FaseModel? faseExistente}) {
    final nomeController = TextEditingController(
      text: faseExistente?.nomeFasePadrao ?? '',
    );
    final nomePublicoController = TextEditingController(
      text: faseExistente?.nomePublico ?? '',
    );
    final descController = TextEditingController(
      text: faseExistente?.descricao ?? '',
    );

    String postoSelecionado =
        faseExistente?.postoTrabalho ?? _postosTrabalhoDisponiveis.first;
    if (!_postosTrabalhoDisponiveis.contains(postoSelecionado)) {
      postoSelecionado = _postosTrabalhoDisponiveis.first;
    }

    final tempoController = TextEditingController(
      text: faseExistente != null
          ? faseExistente.tempoEstimado.toString()
          : '15',
    );

    List<String> checklistLocal = List<String>.from(
      faseExistente?.checklist ?? const [],
    );
    final taskController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                faseExistente == null
                    ? 'Adicionar Fase de Produção'
                    : 'Editar Fase de Produção',
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: larguraDialogo(context, 450),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nomeController,
                        decoration: const InputDecoration(
                          labelText: 'Nome da Fase * (Ex: Corte de Painéis)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nomePublicoController,
                        decoration: const InputDecoration(
                          labelText: 'Nome visível ao cliente (opcional)',
                          helperText:
                              'Em branco, o cliente vê o nome técnico da fase',
                          helperMaxLines: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(
                          labelText: 'Descrição sumária da atividade',
                        ),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: postoSelecionado,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Posto de Trabalho Associado *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _postosTrabalhoDisponiveis.map((posto) {
                          return DropdownMenuItem<String>(
                            value: posto,
                            child: Text(
                              posto,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (novoPosto) {
                          if (novoPosto != null) {
                            setDialogState(() => postoSelecionado = novoPosto);
                          }
                        },
                      ),

                      const SizedBox(height: 12),
                      TextField(
                        controller: tempoController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Tempo Estimado (minutos)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '📋 Checklist SOP (Passos obrigatórios do Operador):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: TemasCores.acentoAzulAcinzentado,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: taskController,
                              decoration: const InputDecoration(
                                labelText:
                                    'Adicionar passo (Ex: Confirmar dimensões)',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: TemasCores.adminAcento,
                            ),
                            onPressed: () {
                              if (taskController.text.isNotEmpty) {
                                setDialogState(() {
                                  checklistLocal.add(
                                    taskController.text.trim(),
                                  );
                                  taskController.clear();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: checklistLocal.length,
                          itemBuilder: (context, idx) {
                            return ListTile(
                              title: Text(
                                checklistLocal[idx],
                                style: const TextStyle(fontSize: 12),
                              ),
                              dense: true,
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: TemasCores.erro,
                                  size: 16,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    checklistLocal.removeAt(idx);
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.trim().isEmpty) {
                      _mostrarErro('O nome da fase é obrigatório.');
                      return;
                    }

                    _salvarFase(
                      id: faseExistente?.id,
                      nome: nomeController.text.trim(),
                      descricao: descController.text.trim(),
                      posto: postoSelecionado,
                      tempo: int.tryParse(tempoController.text) ?? 15,
                      checklist: checklistLocal,
                      nomePublico: nomePublicoController.text,
                    );
                    Navigator.pop(context);
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
