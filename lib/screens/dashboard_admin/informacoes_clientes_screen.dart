import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/paginacao.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import 'widgets/cartao_kpi.dart';
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

  /// Os clientes já carregados — a primeira página mais o que o scroll trouxe.
  ///
  /// Não há aqui lista "filtrada": o filtro e a pesquisa são resolvidos pelo
  /// servidor, porque filtrar em memória sobre uma lista paginada esconderia
  /// todos os clientes que ainda não tivessem sido descarregados.
  List<ClienteModel> _clientes = [];
  MetricasClientes _metricas = const MetricasClientes();
  bool _isLoading = true;
  bool _aCarregarMais = false;
  bool _temMais = false;

  // 🔍 CONTROLADORES E ESTADOS DE FILTRAGEM
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debouncePesquisa;
  FiltroCliente _filtroEstado = FiltroCliente.todos;

  // 🗂️ PAINEL LATERAL (DRAWER DETALHES DO CLIENTE)
  ClienteModel? _clienteDetalhesSelecionado;

  @override
  void initState() {
    super.initState();
    _carregarClientes();
    _carregarMetricas();
    _inicializarSubscricaoRealtime();

    _searchController.addListener(_aoEscreverPesquisa);
    _scrollController.addListener(_aoDeslizar);
  }

  @override
  void dispose() {
    _recarregador.descartar();
    _debouncePesquisa?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    if (_clientesSubscription != null) {
      _clientesRepo.client.removeChannel(_clientesSubscription!);
    }
    super.dispose();
  }

  // --- LIGAÇÃO À BASE DE DADOS & REALTIME (SUPABASE) ---
  //
  // Os quatro helpers defensivos que existiam aqui (_obterTotalEncomendas,
  // _temEncomendas, _obterListaEncomendas, _obterListaPedidos) desapareceram:
  // desembrulhavam à mão as junções vindas do Supabase, trabalho que passou
  // para as fábricas dos modelos.

  /// Um evento aqui custa a lista **e** as quatro métricas do topo. O
  /// recarregador funde as rajadas num só ciclo — e impede que dois corram
  /// sobrepostos, o que podia fazer a resposta mais antiga escrever por cima da
  /// mais recente.
  late final RecarregadorDebounced _recarregador = RecarregadorDebounced(
    aoRecarregar: () async {
      await _recarregarMantendoPosicao();
      await _carregarMetricas();
    },
    janela: janelaRealtimeCarteira,
    tetoEspera: tetoRealtimeCarteira,
  );

  void _inicializarSubscricaoRealtime() {
    _clientesSubscription =
        _clientesRepo.escutarCarteira('db-clientes-realtime', _recarregador.pedir);
  }

  /// Carrega a primeira página, descartando o que estivesse carregado.
  Future<void> _carregarClientes() async {
    try {
      final pagina = await _clientesRepo.obterComHistorico(
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _clientes = pagina.itens;
        _temMais = pagina.temMais;
        _isLoading = false;
        _sincronizarDetalhe();
      });
    } catch (e) {
      _mostrarMensagem('Erro ao carregar base de dados de clientes: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Acrescenta a página seguinte ao fim da lista.
  Future<void> _carregarMais() async {
    if (_aCarregarMais || !_temMais) return;
    setState(() => _aCarregarMais = true);
    try {
      final pagina = await _clientesRepo.obterComHistorico(
        deslocamento: _clientes.length,
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _clientes = [..._clientes, ...pagina.itens];
        _temMais = pagina.temMais;
        _aCarregarMais = false;
      });
    } catch (e) {
      _mostrarMensagem('Erro ao carregar mais clientes: $e', eErro: true);
      if (mounted) setState(() => _aCarregarMais = false);
    }
  }

  /// Repõe as linhas que o utilizador tem à frente, sem o atirar de volta ao topo.
  Future<void> _recarregarMantendoPosicao() async {
    final int carregadas =
        _clientes.length < tamanhoPaginaPadrao ? tamanhoPaginaPadrao : _clientes.length;
    try {
      final pagina = await _clientesRepo.obterComHistorico(
        tamanho: carregadas,
        filtro: _filtroEstado,
        pesquisa: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _clientes = pagina.itens;
        _temMais = pagina.temMais;
        _isLoading = false;
        _sincronizarDetalhe();
      });
    } catch (e) {
      _mostrarMensagem('Erro ao atualizar a carteira de clientes: $e', eErro: true);
    }
  }

  Future<void> _carregarMetricas() async {
    try {
      final metricas = await _clientesRepo.obterMetricas();
      if (mounted) setState(() => _metricas = metricas);
    } catch (e) {
      _mostrarMensagem('Erro ao carregar as métricas de clientes: $e', eErro: true);
    }
  }

  /// Mantém o painel de detalhe a apontar para a versão recarregada do cliente.
  ///
  /// Se o cliente aberto tiver saído da fatia carregada — por o filtro ou a
  /// pesquisa terem mudado — a referência anterior é mantida, para o painel não
  /// se fechar sozinho por baixo de quem está a lê-lo.
  void _sincronizarDetalhe() {
    final selecionado = _clienteDetalhesSelecionado;
    if (selecionado == null) return;
    for (final c in _clientes) {
      if (c.id == selecionado.id) {
        _clienteDetalhesSelecionado = c;
        return;
      }
    }
  }

  void _aoEscreverPesquisa() {
    _debouncePesquisa?.cancel();
    _debouncePesquisa = Timer(esperaPesquisa, () {
      _voltarAoTopo();
      _carregarClientes();
    });
    // Redesenha só para o botão de limpar aparecer/desaparecer de imediato.
    if (mounted) setState(() {});
  }

  void _aoDeslizar() {
    if (!_scrollController.hasClients) return;
    final posicao = _scrollController.position;
    if (posicao.pixels >= posicao.maxScrollExtent - 400) {
      _carregarMais();
    }
  }

  void _voltarAoTopo() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Não há pesquisa nem filtro de estado a restringir a carteira.
  bool get _semFiltrosAtivos =>
      _searchController.text.trim().isEmpty && _filtroEstado == FiltroCliente.todos;

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
      context.mostrarMensagem(msg, eErro: eErro);
    }
  }

  // A formatação do telefone passou para `ClienteModel.contactoFormatado` /
  // `ClienteModel.formatarTelefone`, partilhada com o TelefoneInputFormatter.

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcra,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 📊 CARTÕES DE MÉTRICAS (KPIs DA CARTEIRA DE CLIENTES)
                      _buildKpiCards(),
                      const SizedBox(height: 24),

                      // TABELA DE CLIENTES & FERRAMENTAS DE PESQUISA
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Base de Dados de Clientes',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Gestão de informações fiscais, logísticas e credenciais de acesso',
                                        style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirDialogCliente(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TemasCores.marcaEscura,
                                      foregroundColor: TemasCores.textoInverso,
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
                              //
                              // Só existe uma lista: a que o servidor devolveu já
                              // filtrada. A mensagem distingue "carteira vazia" de
                              // "os filtros não deram resultados" pelo que está
                              // pedido, e não por comparar duas listas em memória.
                              if (_clientes.isEmpty && _semFiltrosAtivos)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text('Nenhum cliente registado na base de dados.', style: TextStyle(color: TemasCores.textoTerciario)),
                                  ),
                                )
                              else if (_clientes.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.search_off_rounded, size: 36, color: TemasCores.textoDesativado),
                                        SizedBox(height: 8),
                                        Text(
                                          'Nenhum cliente encontrado com os filtros aplicados.',
                                          style: TextStyle(color: TemasCores.textoApoio, fontSize: 13, fontWeight: FontWeight.w500),
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
                                      itemCount: _clientes.length,
                                      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                                      itemBuilder: (context, index) {
                                        return _buildClienteRow(_clientes[index]);
                                      },
                                    ),
                                    if (_temMais) _buildRodapePaginacao(),
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
                      color: TemasCores.sombraBase.withOpacity(0.35),
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
        hintStyle: const TextStyle(fontSize: 13, color: TemasCores.textoDesativado),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: TemasCores.textoSecundario),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () => _searchController.clear(),
              )
            : null,
        fillColor: TemasCores.superficieSuave,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildDropdownFiltro() {
    return DropdownButtonFormField<FiltroCliente>(
      value: _filtroEstado,
      decoration: InputDecoration(
        fillColor: TemasCores.superficieSuave,
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: [
        for (final filtro in FiltroCliente.values)
          DropdownMenuItem(
            value: filtro,
            child: Text(filtro.etiqueta, style: const TextStyle(fontSize: 13)),
          ),
      ],
      onChanged: (val) {
        if (val == null) return;
        setState(() => _filtroEstado = val);
        // Mudar de filtro recomeça a paginação do início.
        _voltarAoTopo();
        _carregarClientes();
      },
    );
  }

  /// Rodapé da lista paginada.
  ///
  /// O scroll da página já carrega a fatia seguinte ao aproximar-se do fim; o
  /// botão cobre o caso de a janela ser alta o bastante para não haver scroll.
  Widget _buildRodapePaginacao() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _aCarregarMais
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton.icon(
                onPressed: _carregarMais,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Carregar mais', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }

  // --- WIDGET DOS CARTÕES DE MÉTRICAS (KPIS) ---

  Widget _buildKpiCards() {
    // Vêm do servidor: contados sobre a lista carregada, passariam a descrever o
    // tamanho da página em vez do total da carteira.
    final int totalClientes = _metricas.total;
    final int ativosPortal = _metricas.ativosPortal;
    final int comEncomendas = _metricas.comEncomendas;
    final int totalEncomendas = _metricas.totalEncomendas;

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
              corIcone: TemasCores.marcaEscura,
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Acesso ao Portal',
              valor: '$ativosPortal',
              subtitulo: 'Contas ativas',
              icone: Icons.verified_user_outlined,
              corIcone: TemasCores.sucessoTexto,
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Clientes c/ Encomendas',
              valor: '$comEncomendas',
              subtitulo: 'Com histórico associado',
              icone: Icons.shopping_bag_outlined,
              corIcone: TemasCores.infoTexto,
            ),
            _buildKpiCard(
              largura: cardWidth,
              titulo: 'Volume de Encomendas',
              valor: '$totalEncomendas',
              subtitulo: 'Total acumulado',
              icone: Icons.inventory_2_outlined,
              corIcone: TemasCores.avisoTexto,
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
    return CartaoKpi(
      estilo: EstiloKpi.clientes,
      largura: largura,
      titulo: titulo,
      valor: valor,
      subtitulo: subtitulo,
      icone: icone,
      corIcone: corIcone,
    );
  }

  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: const [
          Expanded(
            flex: 3,
            child: Text('Cliente & NIF', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
          ),
          Expanded(
            flex: 3,
            child: Text('Contacto / Interlocutor', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Histórico', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Text('Acesso ao Portal', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13)),
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
          style: const TextStyle(fontWeight: FontWeight.w600, color: TemasCores.textoPrimario, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (nif.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: TemasCores.borda,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NIF $nif',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: TemasCores.textoApoioIntenso),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.email_outlined, size: 12, color: TemasCores.textoDesativado),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                cliente.email ?? 'Sem email',
                style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 12),
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
            const Icon(Icons.phone_outlined, size: 14, color: TemasCores.textoDesativado),
            const SizedBox(width: 6),
            Text(
              cliente.contactoFormatado,
              style: const TextStyle(color: TemasCores.textoApoioForte, fontSize: 13, fontWeight: FontWeight.w500),
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
              color: TemasCores.superficie,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TemasCores.bordaForte),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_toggle_off_rounded, size: 13, color: TemasCores.textoApoio),
                const SizedBox(width: 6),
                Text(
                  '${cliente.totalEncomendas} encomendas',
                  style: const TextStyle(color: TemasCores.textoApoioForte, fontSize: 12, fontWeight: FontWeight.w600),
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
            color: cliente.ativo ? TemasCores.estadoAtivoFundo : TemasCores.estadoInativoFundo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            cliente.ativo ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: cliente.ativo ? TemasCores.textoInverso : TemasCores.textoSecundario,
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
          side: const BorderSide(color: TemasCores.bordaForte),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        icon: const Icon(Icons.edit_outlined, size: 14, color: TemasCores.textoPrimario),
        label: const Text('Editar Dados',
            style: TextStyle(color: TemasCores.textoPrimario, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }

  /// Linha compacta de ícone + texto, repetida nas colunas de identificação e contacto.
  Widget _buildLinhaIcone(IconData icone, String texto,
      {double tamanho = 12, FontWeight peso = FontWeight.normal}) {
    return Row(
      children: [
        Icon(icone, size: 12, color: TemasCores.textoDesativado),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(color: TemasCores.textoTerciario, fontSize: tamanho, fontWeight: peso),
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
        color: TemasCores.superficie,
        boxShadow: [
          BoxShadow(color: TemasCores.sombraMarcada, blurRadius: 16, offset: Offset(-4, 0)),
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
        color: TemasCores.marcaEscura,
        border: const Border(bottom: BorderSide(color: TemasCores.bordaEscura)),
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
                  style: const TextStyle(color: TemasCores.textoInverso, fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: TemasCores.textoInversoAtenuado),
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
                  decoration: BoxDecoration(color: TemasCores.realceSobreEscuroForte, borderRadius: BorderRadius.circular(4)),
                  child: Text('NIF: $nif',
                      style: const TextStyle(color: TemasCores.textoInversoAtenuado, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cliente.ativo ? TemasCores.sucessoTextoForte : TemasCores.erroTextoForte,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cliente.ativo ? 'Portal Ativo' : 'Portal Bloqueado',
                  style: const TextStyle(color: TemasCores.textoInverso, fontSize: 11, fontWeight: FontWeight.bold),
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TemasCores.superficieTenue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: TemasCores.borda),
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
          fundoContador: TemasCores.infoFundo,
          corContador: TemasCores.infoTextoForte,
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
                      BoxDecoration(color: TemasCores.avisoFundo, borderRadius: BorderRadius.circular(4)),
                  child: Text(p.estado.etiqueta,
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.bold, color: TemasCores.avisoTextoForte)),
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
          fundoContador: TemasCores.superficieSuave,
          corContador: TemasCores.textoApoioIntenso,
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
                  style: const TextStyle(fontSize: 11, color: TemasCores.textoTerciario, fontWeight: FontWeight.w500),
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
        Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
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
        style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciario, fontStyle: FontStyle.italic));
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
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: TemasCores.textoPrimario)),
              Text(subtitulo, style: const TextStyle(fontSize: 11, color: TemasCores.textoApoio)),
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
        Icon(icone, size: 16, color: TemasCores.textoApoio),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(titulo, style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
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
                        activeColor: TemasCores.textoPrimario,
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