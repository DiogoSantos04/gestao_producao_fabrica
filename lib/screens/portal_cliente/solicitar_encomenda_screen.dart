import 'package:flutter/material.dart';

import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/pedido_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../widgets/etiqueta_estado.dart';

class SolicitarEncomendaScreen extends StatefulWidget {
  const SolicitarEncomendaScreen({super.key});

  @override
  State<SolicitarEncomendaScreen> createState() => SolicitarEncomendaScreenState();
}

class SolicitarEncomendaScreenState extends State<SolicitarEncomendaScreen> {
  final PortalClienteRepository _repositorio = PortalClienteRepository();
  final _formKey = GlobalKey<FormState>();

  final _quantidadeController = TextEditingController(text: '1');
  final _observacoesController = TextEditingController();

  List<TipoProdutoOpcao> _tiposProduto = [];
  List<PedidoModel> _meusPedidos = [];
  int? _tipoProdutoSelecionadoId;

  /// Filtro da lista "Os Meus Pedidos"; `null` mostra todos os estados.
  EstadoPedido? _filtroEstado;

  /// Abaixo desta largura as duas colunas colapsam para uma só.
  static const double _larguraMinimaDuasColunas = 1050;

  bool _carregandoInicial = true;
  bool _submetendo = false;
  int? _clienteId;
  String? _erroInicial;

  /// Repetição pedida no histórico antes de a lista de artigos estar carregada.
  int? _repeticaoPendente;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  @override
  void dispose() {
    _quantidadeController.dispose();
    _observacoesController.dispose();
    super.dispose();
  }

  /// Preenche o formulário a partir de uma encomenda anterior ("Repetir Pedido").
  ///
  /// O artigo é validado contra a lista carregada: atribuir ao dropdown um id
  /// que já não existe (artigo removido no painel de administração) fazia
  /// rebentar a asserção do `DropdownButtonFormField` e deixava o ecrã inutilizável
  /// — ver bug (F).
  void preencherParaRepeticao({required int tipoProdutoId, required int quantidade}) {
    setState(() {
      _quantidadeController.text = quantidade.toString();
      _repeticaoPendente = tipoProdutoId;
    });
    if (!_carregandoInicial) _aplicarRepeticaoPendente();
  }

  void _aplicarRepeticaoPendente() {
    final id = _repeticaoPendente;
    if (id == null) return;
    _repeticaoPendente = null;

    final existe = _tiposProduto.any((t) => t.id == id);
    if (!mounted) return;

    if (existe) {
      setState(() => _tipoProdutoSelecionadoId = id);
      return;
    }

    context.mostrarSnack(
      'O artigo dessa encomenda já não está disponível. Selecione outro da lista.',
      cor: TemasCores.alerta,
    );
  }

  Future<void> _carregarDadosIniciais() async {
    if (mounted) {
      setState(() {
        _carregandoInicial = true;
        _erroInicial = null;
      });
    }

    try {
      final produtos = await _repositorio.obterTiposProduto();
      // A identidade do cliente vem da chave estrangeira `clientes.utilizador_id`
      // e não da comparação de nomes que existia aqui — ver bug (A).
      final cliente = await _repositorio.obterClienteAutenticado();
      final pedidos = cliente == null ? <PedidoModel>[] : await _repositorio.obterMeusPedidos(cliente.id);

      if (!mounted) return;
      setState(() {
        _tiposProduto = produtos;
        _meusPedidos = pedidos;
        _clienteId = cliente?.id;

        // Uma seleção anterior deixa de ser válida se o artigo tiver saído da lista.
        if (_tipoProdutoSelecionadoId != null && !produtos.any((t) => t.id == _tipoProdutoSelecionadoId)) {
          _tipoProdutoSelecionadoId = null;
        }
        _tipoProdutoSelecionadoId ??= produtos.isNotEmpty ? produtos.first.id : null;
        _carregandoInicial = false;
      });

      _aplicarRepeticaoPendente();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _erroInicial = e.mensagem;
        _carregandoInicial = false;
      });
    }
  }

  Future<void> _submeterPedido() async {
    if (!_formKey.currentState!.validate()) return;

    final clienteId = _clienteId;
    if (clienteId == null) {
      context.mostrarSnack(
        'A sua conta ainda não está associada a um registo de cliente. '
        'Contacte-nos para concluir o registo.',
        cor: TemasCores.alerta,
      );
      return;
    }

    final tipoProdutoId = _tipoProdutoSelecionadoId;
    if (tipoProdutoId == null) {
      context.mostrarSnack('Por favor, selecione um artigo da lista.', cor: TemasCores.alerta);
      return;
    }

    setState(() => _submetendo = true);

    try {
      await _repositorio.submeterPedido(
        clienteId: clienteId,
        tipoProdutoId: tipoProdutoId,
        quantidade: int.parse(_quantidadeController.text.trim()),
        observacoes: _observacoesController.text,
      );

      // A lista de pedidos é relida logo a seguir para o cliente ver o pedido
      // que acabou de submeter — sem isso, não tinha como saber que já o tinha
      // feito e voltava a submeter o mesmo.
      final pedidos = await _repositorio.obterMeusPedidos(clienteId);

      if (!mounted) return;
      setState(() {
        _submetendo = false;
        _observacoesController.clear();
        _quantidadeController.text = '1';
        _meusPedidos = pedidos;
        // Sem isto, um filtro ativo podia esconder o pedido acabado de submeter.
        _filtroEstado = null;
      });

      context.mostrarMensagem('Pedido enviado com sucesso! O Administrador irá analisar a solicitação.');
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _submetendo = false);
      context.mostrarMensagem(e.mensagem, eErro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: _carregandoInicial
          ? const Center(child: CircularProgressIndicator(color: TemasCores.clienteAcento))
          : _erroInicial != null
          ? _construirErroInicial()
          : LayoutBuilder(
              builder: (context, constraints) {
                final duasColunas = constraints.maxWidth >= _larguraMinimaDuasColunas;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: duasColunas ? 1280 : 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (duasColunas)
                            // `IntrinsicHeight` + `stretch` iguala a altura dos
                            // dois cartões: com alturas livres, a coluna mais
                            // curta ficava a "flutuar" e o bloco parecia torto.
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // 40 / 60: o formulário é compacto e a lista de
                                  // pedidos é a que ganha com a largura extra.
                                  Expanded(flex: 40, child: _construirColunaFormulario(esticar: true)),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 60, child: _construirColunaPedidos(esticar: true)),
                                ],
                              ),
                            )
                          else ...[
                            _construirColunaFormulario(esticar: false),
                            const SizedBox(height: 32),
                            _construirColunaPedidos(esticar: false),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _construirErroInicial() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: TemasCores.erro, size: 40),
          const SizedBox(height: 12),
          Text(
            _erroInicial!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: TemasCores.erroTextoForte, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _carregarDadosIniciais,
            style: OutlinedButton.styleFrom(foregroundColor: TemasCores.clienteAcento),
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  /// Cabeçalho de coluna, com altura fixa para os dois cartões arrancarem
  /// exatamente à mesma cota — sem isto, o ícone de atualizar da direita
  /// empurrava o cartão para baixo e as colunas ficavam desniveladas.
  Widget _construirCabecalhoColuna({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required bool esticar,
    Widget? acao,
  }) {
    final conteudo = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: TemasCores.clienteAcento.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, size: 23, color: TemasCores.clienteAcento),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.textoPrimarioFrio,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: TemasCores.textoSecundarioFrio),
              ),
            ],
          ),
        ),
        ?acao,
      ],
    );

    // A altura fixa só serve para alinhar os dois cartões lado a lado no
    // layout de duas colunas. Em coluna única (`esticar: false`) o título de
    // 24px pode quebrar em duas linhas em ecrã estreito, e uma altura fixa
    // cortava-o — ver overflow reportado em 400px de largura.
    return esticar ? SizedBox(height: 62, child: conteudo) : conteudo;
  }

  /// Envolve o conteúdo de uma coluna no cartão. Com `esticar`, o cartão ocupa
  /// toda a altura disponível para as duas colunas terminarem alinhadas.
  Widget _construirCartaoColuna({required bool esticar, required Widget conteudo}) {
    final cartao = Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(padding: const EdgeInsets.all(24.0), child: conteudo),
    );
    return esticar ? Expanded(child: cartao) : cartao;
  }

  Widget _construirColunaFormulario({required bool esticar}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _construirCabecalhoColuna(
          icone: Icons.add_shopping_cart_outlined,
          titulo: 'Solicitar Nova Encomenda',
          subtitulo: 'Preencha os dados e submeta a solicitação.',
          esticar: esticar,
        ),
        const SizedBox(height: 16),
        _construirCartaoColuna(esticar: esticar, conteudo: _construirFormulario()),
      ],
    );
  }

  /// Pedidos já submetidos por este cliente, com o estado de cada um.
  ///
  /// O formulário aceitava o pedido e nunca mais mostrava nada: o cliente não
  /// sabia se estava pendente, aprovado ou rejeitado — nem sequer que já o
  /// tinha submetido, pelo que voltava a submetê-lo.
  Widget _construirColunaPedidos({required bool esticar}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _construirCabecalhoColuna(
          icone: Icons.receipt_long_outlined,
          titulo: 'Os Meus Pedidos',
          subtitulo: 'Estado das solicitações que enviou para a nossa equipa.',
          esticar: esticar,
          acao: IconButton(
            icon: const Icon(Icons.refresh),
            color: TemasCores.clienteAcento,
            tooltip: 'Atualizar',
            onPressed: _carregarDadosIniciais,
          ),
        ),
        const SizedBox(height: 16),
        _construirCartaoColuna(
          esticar: esticar,
          conteudo: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_meusPedidos.isNotEmpty) ...[_construirFiltros(), const SizedBox(height: 16)],
              if (_meusPedidos.isEmpty)
                _construirCaixaVazia('Ainda não submeteu nenhum pedido.')
              else if (_pedidosFiltrados.isEmpty)
                _construirCaixaVazia('Nenhum pedido ${_filtroEstado!.etiqueta.toLowerCase()}.')
              else
                ..._pedidosFiltrados.map(_construirCartaoPedido),
            ],
          ),
        ),
      ],
    );
  }

  List<PedidoModel> get _pedidosFiltrados {
    final filtro = _filtroEstado;
    if (filtro == null) return _meusPedidos;
    return _meusPedidos.where((p) => p.estado == filtro).toList();
  }

  /// Chips de estado: com muitos pedidos a lista deixa de ser consultável sem filtro.
  ///
  /// Só se mostram os estados que o cliente tem de facto, para não oferecer
  /// filtros que garantidamente dão lista vazia.
  Widget _construirFiltros() {
    final estadosPresentes = EstadoPedido.values
        .where((e) => _meusPedidos.any((p) => p.estado == e))
        .toList();

    Widget chip(String rotulo, EstadoPedido? estado, int contagem) {
      final ativo = _filtroEstado == estado;
      return ChoiceChip(
        label: Text('$rotulo ($contagem)'),
        selected: ativo,
        onSelected: (_) => setState(() => _filtroEstado = estado),
        showCheckmark: false,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
          color: ativo ? TemasCores.textoInverso : TemasCores.textoSecundarioFrio,
        ),
        backgroundColor: TemasCores.superficie,
        selectedColor: TemasCores.clienteAcento,
        side: const BorderSide(color: TemasCores.borda),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip('Todos', null, _meusPedidos.length),
        for (final estado in estadosPresentes)
          chip(estado.etiqueta, estado, _meusPedidos.where((p) => p.estado == estado).length),
      ],
    );
  }

  Widget _construirCaixaVazia(String mensagem) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Text(mensagem, style: const TextStyle(color: TemasCores.textoSecundarioFrio)),
    );
  }

  Widget _construirCartaoPedido(PedidoModel pedido) {
    final cores = coresEstadoPedido(pedido.estado);
    final IconData icone = switch (pedido.estado) {
      EstadoPedido.pendente => Icons.hourglass_empty,
      EstadoPedido.aprovado => Icons.check_circle_outline,
      EstadoPedido.emProducao => Icons.precision_manufacturing_outlined,
      EstadoPedido.rejeitado => Icons.cancel_outlined,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      // Fundo mais frio que o do cartão da coluna: um cartão branco dentro de
      // outro branco perdia-se completamente.
      color: TemasCores.fundoEcraFrio,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: cores.texto, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${pedido.nomeProduto ?? 'Artigo'} (${pedido.quantidade} unid.)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      EtiquetaEstado.pilula(
                        rotulo: pedido.estado.etiqueta.toUpperCase(),
                        fundo: cores.fundo,
                        texto: cores.texto,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submetido a ${_formatarData(pedido.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: TemasCores.textoSecundarioFrio),
                  ),
                  if (pedido.temObservacoes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        pedido.observacoes!,
                        style: const TextStyle(fontSize: 12, color: TemasCores.textoApoioFrio),
                      ),
                    ),
                  if (pedido.estado == EstadoPedido.pendente)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'A aguardar análise da nossa equipa.',
                        style: TextStyle(fontSize: 12, color: TemasCores.textoTerciarioFrio),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'data desconhecida';
    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _construirFormulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Artigo / Tipo de Produto',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: TemasCores.textoApoioForteFrio,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            // `value` está deprecado a favor de `initialValue`, mas este só é
            // lido na construção do campo: com ele, o "Repetir Pedido" deixaria
            // de conseguir mudar a seleção a partir do histórico. Mantém-se
            // `value` até a migração das deprecações ser feita em todo o repo.
            // ignore: deprecated_member_use
            value: _tipoProdutoSelecionadoId,
            // Sem isto, o item selecionado não encolhe para dar espaço à seta
            // — em ecrã estreito, um nome de artigo um pouco mais comprido
            // empurrava a seta para fora do campo (overflow à direita).
            isExpanded: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              prefixIcon: const Icon(Icons.inventory_2_outlined, color: TemasCores.clienteAcento),
            ),
            hint: const Text('Selecione um artigo'),
            items: _tiposProduto
                .map((prod) => DropdownMenuItem<int>(
                      value: prod.id,
                      child: Text(prod.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (val) => setState(() => _tipoProdutoSelecionadoId = val),
            validator: (v) => v == null ? 'Selecione um artigo.' : null,
          ),
          const SizedBox(height: 20),
          const Text(
            'Quantidade Pretendida',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: TemasCores.textoApoioForteFrio,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _quantidadeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.format_list_numbered, color: TemasCores.clienteAcento),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Insira a quantidade.';
              final n = int.tryParse(val.trim());
              if (n == null || n <= 0) return 'Insira um valor maior que 0.';
              return null;
            },
          ),
          const SizedBox(height: 20),
          const Text(
            'Observações / Especificações Especiais',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: TemasCores.textoApoioForteFrio,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _observacoesController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Escreva detalhes adicionais sobre cores, acabamentos ou prazos pretendidos...',
              hintStyle: const TextStyle(color: TemasCores.textoTerciarioFrio, fontSize: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _submetendo ? null : _submeterPedido,
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.clienteAcento,
              foregroundColor: TemasCores.textoInverso,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _submetendo
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _submetendo ? 'A Enviar Pedido...' : 'Submeter Pedido de Encomenda',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
