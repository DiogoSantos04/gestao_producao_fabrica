import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/mensagens.dart';
import '../../core/paginacao.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import 'dialogos/dialogo_cliente.dart';
import 'widgets/barra_filtros_clientes.dart';
import 'widgets/kpis_carteira_clientes.dart';
import 'widgets/linha_cliente.dart';
import 'widgets/painel_detalhe_cliente.dart';
import '../../models/cliente_model.dart';
import '../../repositories/clientes_repository.dart';
import '../../repositories/utilizadores_repository.dart';
import '../../widgets/estado_erro.dart';
import '../../widgets/rodape_paginacao.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _clientesRepo = ClientesRepository();
  final _utilizadoresRepo = UtilizadoresRepository();
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

  /// Motivo da última falha a ler a carteira, ou `null` se correu bem. A
  /// mensagem "nenhum cliente registado" é uma afirmação sobre o negócio: não
  /// pode ser o que se vê quando o que falhou foi a ligação.
  String? _erroCarregamento;

  /// Falha a acrescentar a página seguinte — só o rodapé muda.
  String? _erroPaginacao;

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
        _erroCarregamento = null;
        _erroPaginacao = null;
        _sincronizarDetalhe();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _erroCarregamento = descreverErro(e);
        });
      }
    }
  }

  /// Acrescenta a página seguinte ao fim da lista.
  Future<void> _carregarMais() async {
    if (_aCarregarMais || !_temMais) return;
    setState(() {
      _aCarregarMais = true;
      _erroPaginacao = null;
    });
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
      if (mounted) {
        setState(() {
          _aCarregarMais = false;
          _erroPaginacao = descreverErro(e);
        });
      }
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
        _erroCarregamento = null;
        _sincronizarDetalhe();
      });
    } catch (e) {
      if (mounted) setState(() => _erroCarregamento = descreverErro(e));
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
    // O botão de limpar já não precisa de um `setState` do ecrã inteiro: a
    // barra de filtros observa o próprio controlador.
  }

  void _aoDeslizar() {
    if (!_scrollController.hasClients) return;
    // Depois de uma falha o scroll deixa de pedir sozinho: a retoma é do
    // utilizador, pelo botão de repetir no rodapé.
    if (_erroPaginacao != null) return;
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

  /// Cria a ficha do cliente e, se pedido, a conta de acesso que lhe fica
  /// associada.
  ///
  /// A credencial é criada primeiro de propósito: é ela que produz a linha em
  /// `utilizadores` para onde `clientes.utilizador_id` aponta. Se falhar, não se
  /// chega a criar ficha nenhuma — melhor não ter cliente do que ter um cliente
  /// que se dizia com acesso e não tem.
  Future<void> _inserirCliente({
    required String nome,
    required String email,
    required String contacto,
    required String nif,
    required String pessoaContacto,
    required String morada,
    required bool ativo,
    String? passwordAcesso,
  }) async {
    try {
      setState(() => _isLoading = true);

      String? utilizadorId;
      if (passwordAcesso != null) {
        utilizadorId = await _utilizadoresRepo.criarCredencialCliente(
          nome: nome,
          email: email,
          password: passwordAcesso,
        );
      }

      await _clientesRepo.criar({
        'nome_cliente': nome,
        'email': email,
        'contacto': contacto,
        'nif': nif,
        'pessoa_contacto': pessoaContacto,
        'morada': morada,
        'ativo': ativo,
        'utilizador_id': ?utilizadorId,
      });
      _mostrarMensagem(utilizadorId == null
          ? 'Cliente criado com sucesso!'
          : 'Cliente criado e já disponível em Utilizadores!');
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

  /// Abre o formulário de cliente e grava o que ele devolver.
  ///
  /// É o mesmo formulário para criar e para editar; o que muda é a escrita, e
  /// essa decisão fica aqui porque é aqui que vive o `_isLoading`.
  Future<void> _abrirDialogCliente({ClienteModel? clienteExistente}) async {
    final dados = await DialogoCliente.mostrar(context, clienteExistente: clienteExistente);
    if (dados == null || !mounted) return;

    if (clienteExistente == null) {
      await _inserirCliente(
        nome: dados.nome,
        email: dados.email,
        contacto: dados.contacto,
        nif: dados.nif,
        pessoaContacto: dados.pessoaContacto,
        morada: dados.morada,
        ativo: dados.ativo,
        passwordAcesso: dados.passwordAcesso,
      );
    } else {
      await _atualizarCliente(
        id: clienteExistente.id,
        nome: dados.nome,
        email: dados.email,
        contacto: dados.contacto,
        nif: dados.nif,
        pessoaContacto: dados.pessoaContacto,
        morada: dados.morada,
        ativo: dados.ativo,
      );
    }
  }

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
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
                      KpisCarteiraClientes(metricas: _metricas),
                      const SizedBox(height: 24),

                      // TABELA DE CLIENTES & FERRAMENTAS DE PESQUISA
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Base de Dados de Clientes',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Gestão de informações fiscais, logísticas e credenciais de acesso',
                                        style: TextStyle(fontSize: 13, color: TemasCores.textoTerciario),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirDialogCliente(),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: TemasCores.adminAcento,
                                      foregroundColor: TemasCores.textoInverso,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('Criar Conta de Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // 🔍 BARRA DE PESQUISA E FILTROS RÁPIDOS
                              BarraFiltrosClientes(
                                controladorPesquisa: _searchController,
                                filtro: _filtroEstado,
                                aoMudarFiltro: (val) {
                                  setState(() => _filtroEstado = val);
                                  // Mudar de filtro recomeça a paginação do início.
                                  _voltarAoTopo();
                                  _carregarClientes();
                                },
                              ),
                              const SizedBox(height: 24),

                              // TABELA OU MENSAGEM VAZIA
                              //
                              // Só existe uma lista: a que o servidor devolveu já
                              // filtrada. A mensagem distingue "carteira vazia" de
                              // "os filtros não deram resultados" pelo que está
                              // pedido, e não por comparar duas listas em memória.
                              // A falha vem primeiro: sem ela, uma carteira que
                              // não se conseguiu ler passava por uma carteira
                              // vazia.
                              if (_clientes.isEmpty && _erroCarregamento != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: EstadoErro(
                                    titulo: 'Não foi possível carregar a base de dados de clientes',
                                    detalhe: _erroCarregamento,
                                    aoRepetir: () {
                                      setState(() => _isLoading = true);
                                      _carregarClientes();
                                    },
                                  ),
                                )
                              else if (_clientes.isEmpty && _semFiltrosAtivos)
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
                                    if (_erroCarregamento != null)
                                      EstadoErro.compacto(
                                        titulo: 'A carteira pode estar desatualizada — falhou a última atualização.',
                                        detalhe: _erroCarregamento,
                                        aoRepetir: _carregarClientes,
                                      ),
                                    const CabecalhoTabelaClientes(),
                                    const Divider(height: 1, thickness: 1),
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _clientes.length,
                                      separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
                                      itemBuilder: (context, index) {
                                        final cliente = _clientes[index];
                                        return LinhaCliente(
                                          cliente: cliente,
                                          aoAbrirDetalhe: () =>
                                              setState(() => _clienteDetalhesSelecionado = cliente),
                                          aoEditar: () => _abrirDialogCliente(clienteExistente: cliente),
                                        );
                                      },
                                    ),
                                    if (_temMais)
                                      RodapePaginacao(
                                        aCarregar: _aCarregarMais,
                                        erro: _erroPaginacao,
                                        aoCarregarMais: _carregarMais,
                                        tituloErro: 'Não foi possível carregar mais clientes.',
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
                      color: TemasCores.sombraBase.withValues(alpha: 0.35),
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 520,
                    child: PainelDetalheCliente(
                      cliente: _clienteDetalhesSelecionado!,
                      aoFechar: () => setState(() => _clienteDetalhesSelecionado = null),
                    ),
                  ),
                ],
              ],
            ),
    );
  }


}