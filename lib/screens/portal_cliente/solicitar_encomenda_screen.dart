import 'package:flutter/material.dart';

import '../../models/pedido_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';

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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('O artigo dessa encomenda já não está disponível. Selecione outro da lista.'),
        backgroundColor: Colors.orange,
      ),
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
      final pedidos =
          cliente == null ? <PedidoModel>[] : await _repositorio.obterMeusPedidos(cliente.id);

      if (!mounted) return;
      setState(() {
        _tiposProduto = produtos;
        _meusPedidos = pedidos;
        _clienteId = cliente?.id;

        // Uma seleção anterior deixa de ser válida se o artigo tiver saído da lista.
        if (_tipoProdutoSelecionadoId != null &&
            !produtos.any((t) => t.id == _tipoProdutoSelecionadoId)) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A sua conta ainda não está associada a um registo de cliente. '
              'Contacte-nos para concluir o registo.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final tipoProdutoId = _tipoProdutoSelecionadoId;
    if (tipoProdutoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione um artigo da lista.'),
          backgroundColor: Colors.orange,
        ),
      );
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
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pedido enviado com sucesso! O Administrador irá analisar a solicitação.'),
          backgroundColor: Colors.green,
        ),
      );
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _submetendo = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensagem), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _carregandoInicial
          ? const Center(child: CircularProgressIndicator())
          : _erroInicial != null
              ? _construirErroInicial()
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Solicitar Nova Encomenda',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Selecione o artigo pretendido e submeta o pedido para a nossa equipa de produção.',
                            style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 32),
                          _construirFormulario(),
                          const SizedBox(height: 40),
                          _construirMeusPedidos(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _construirErroInicial() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 40),
          const SizedBox(height: 12),
          Text(
            _erroInicial!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _carregarDadosIniciais,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }

  /// Pedidos já submetidos por este cliente, com o estado de cada um.
  ///
  /// O formulário aceitava o pedido e nunca mais mostrava nada: o cliente não
  /// sabia se estava pendente, aprovado ou rejeitado — nem sequer que já o
  /// tinha submetido, pelo que voltava a submetê-lo.
  Widget _construirMeusPedidos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Os Meus Pedidos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar',
              onPressed: _carregarDadosIniciais,
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Estado das solicitações que enviou para a nossa equipa.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        if (_meusPedidos.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Text(
              'Ainda não submeteu nenhum pedido.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ..._meusPedidos.map(_construirCartaoPedido),
      ],
    );
  }

  Widget _construirCartaoPedido(PedidoModel pedido) {
    final (Color fundo, Color texto, IconData icone) = switch (pedido.estado) {
      EstadoPedido.pendente => (Colors.amber.shade100, Colors.amber.shade900, Icons.hourglass_empty),
      EstadoPedido.aprovado => (Colors.green.shade100, Colors.green.shade900, Icons.check_circle_outline),
      EstadoPedido.emProducao => (Colors.blue.shade100, Colors.blue.shade900, Icons.precision_manufacturing_outlined),
      EstadoPedido.rejeitado => (Colors.red.shade100, Colors.red.shade900, Icons.cancel_outlined),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, color: texto, size: 22),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          pedido.estado.etiqueta.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: texto),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Submetido a ${_formatarData(pedido.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  if (pedido.temObservacoes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        pedido.observacoes!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      ),
                    ),
                  if (pedido.estado == EstadoPedido.pendente)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'A aguardar análise da nossa equipa.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Artigo / Tipo de Produto',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                // `value` está deprecado a favor de `initialValue`, mas este só é
                // lido na construção do campo: com ele, o "Repetir Pedido" deixaria
                // de conseguir mudar a seleção a partir do histórico. Mantém-se
                // `value` até a migração das deprecações ser feita em todo o repo.
                // ignore: deprecated_member_use
                value: _tipoProdutoSelecionadoId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.deepPurple),
                ),
                hint: const Text('Selecione um artigo'),
                items: _tiposProduto
                    .map((prod) => DropdownMenuItem<int>(value: prod.id, child: Text(prod.nome)))
                    .toList(),
                onChanged: (val) => setState(() => _tipoProdutoSelecionadoId = val),
                validator: (v) => v == null ? 'Selecione um artigo.' : null,
              ),
              const SizedBox(height: 20),
              const Text(
                'Quantidade Pretendida',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _quantidadeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.format_list_numbered, color: Colors.deepPurple),
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _observacoesController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Escreva detalhes adicionais sobre cores, acabamentos ou prazos pretendidos...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _submetendo ? null : _submeterPedido,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _submetendo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _submetendo ? 'A Enviar Pedido...' : 'Submeter Pedido de Encomenda',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
