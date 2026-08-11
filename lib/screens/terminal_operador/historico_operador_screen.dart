import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/breakpoints.dart';
import '../../core/ecra_recarregavel.dart';
import '../../core/formatos.dart';
import '../../core/paginacao.dart';
import '../../core/temas_cores.dart';
import '../../repositories/operador_repository.dart';
import '../../widgets/estado_erro.dart';

class HistoricoOperadorScreen extends StatefulWidget {
  const HistoricoOperadorScreen({super.key});

  @override
  State<HistoricoOperadorScreen> createState() =>
      _HistoricoOperadorScreenState();
}

class _HistoricoOperadorScreenState extends State<HistoricoOperadorScreen>
    implements EcraRecarregavel {
  final OperadorRepository _repo = OperadorRepository();
  final TextEditingController _pesquisaController = TextEditingController();

  List<RegistoDeTurno> _registos = [];
  bool _aCarregar = true;
  bool _aCarregarMais = false;
  bool _temMais = false;
  String? _erro;

  /// Número de páginas já pedidas ao servidor.
  ///
  /// O deslocamento não pode sair de `_registos.length`: o filtro "apenas
  /// bloqueados" é aplicado depois de o servidor responder, pelo que a lista
  /// visível é mais curta do que o que já foi lido e a página seguinte saltaria
  /// registos.
  int _paginas = 0;

  Timer? _debouncePesquisa;

  DateTime? _dia;
  OrdenacaoHistorico _ordenacao = OrdenacaoHistorico.data;
  bool _ascendente = false; // mais recentes primeiro
  bool _apenasBloqueados = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    _pesquisaController.addListener(_aoEscreverPesquisa);
  }

  @override
  void dispose() {
    _debouncePesquisa?.cancel();
    _pesquisaController.dispose();
    super.dispose();
  }

  /// A pesquisa vai ao servidor, por isso não pode disparar a cada tecla.
  void _aoEscreverPesquisa() {
    _debouncePesquisa?.cancel();
    _debouncePesquisa = Timer(esperaPesquisa, _carregar);
  }

  /// Recarregamento pedido pelo shell ao voltar a este separador.
  ///
  /// Recomeça na primeira página com os filtros que estiverem postos: o que
  /// interessa a quem volta ao separador é ver o topo atualizado, não repetir
  /// as páginas que já tinha percorrido.
  @override
  Future<void> recarregar() => _carregar();

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _aCarregar = true;
      _erro = null;
    });

    try {
      final pagina = await _pedirPagina(0);
      if (!mounted) return;
      setState(() {
        _registos = pagina.itens;
        _temMais = pagina.temMais;
        _paginas = 1;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = descreverErro(e);
        _aCarregar = false;
      });
    }
  }

  Future<void> _carregarMais() async {
    if (_aCarregarMais || !_temMais) return;
    setState(() => _aCarregarMais = true);

    try {
      final pagina = await _pedirPagina(_paginas * tamanhoPaginaPadrao);
      if (!mounted) return;
      setState(() {
        _registos = [..._registos, ...pagina.itens];
        _temMais = pagina.temMais;
        _paginas++;
        _aCarregarMais = false;
        // Sem isto, a barra de erro de uma tentativa falhada ficava no ecrã
        // para sempre, mesmo depois de o "Repetir" ter corrido bem.
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = descreverErro(e);
        _aCarregarMais = false;
      });
    }
  }

  Future<PaginaResultado<RegistoDeTurno>> _pedirPagina(int deslocamento) {
    return _repo.obterHistorico(
      deslocamento: deslocamento,
      pesquisa: _pesquisaController.text,
      dia: _dia,
      ordenacao: _ordenacao,
      ascendente: _ascendente,
      apenasBloqueados: _apenasBloqueados,
    );
  }

  /// Qualquer mudança de filtro ou de ordenação recomeça na primeira página:
  /// o critério mudou, e as páginas já lidas foram lidas com o critério antigo.
  void _aplicar(VoidCallback alteracao) {
    setState(alteracao);
    _carregar();
  }

  Future<void> _selecionarData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dia ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: TemasCores.operadorAcentoForte,
            onPrimary: TemasCores.textoInverso,
            onSurface: TemasCores.textoPrimarioFrio,
          ),
        ),
        child: child!,
      ),
    );

    if (escolhida != null) _aplicar(() => _dia = escolhida);
  }

  void _alternarOrdenacao(OrdenacaoHistorico coluna) {
    _aplicar(() {
      if (_ordenacao == coluna) {
        _ascendente = !_ascendente;
      } else {
        _ordenacao = coluna;
        _ascendente = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: Padding(
        padding: paddingEcra(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        TemasCores.operadorAcentoClaro,
                        TemasCores.operadorAcentoForte,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.history_toggle_off,
                    color: TemasCores.textoInverso,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Histórico de Produção',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.textoPrimarioFrio,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Consulte as suas tarefas concluídas ou bloqueios registados',
                        style: TextStyle(
                          fontSize: 14,
                          color: TemasCores.textoSecundarioFrio,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _construirFiltros(),
            const SizedBox(height: 24),
            Expanded(child: _construirTabela()),
          ],
        ),
      ),
    );
  }

  Widget _construirFiltros() {
    final rotuloData = _dia == null
        ? 'Filtrar por Data'
        : '${_dia!.day.toString().padLeft(2, '0')}/'
            '${_dia!.month.toString().padLeft(2, '0')}/${_dia!.year}';

    final campoPesquisa = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: TextField(
          controller: _pesquisaController,
          decoration: const InputDecoration(
            hintText: 'Pesquisar por ID...',
            hintStyle: TextStyle(
              color: TemasCores.textoDesativado,
              fontSize: 14,
            ),
            border: InputBorder.none,
            icon: Icon(Icons.search, color: TemasCores.textoTerciario),
          ),
        ),
      ),
    );

    // O estado deixou de ser um cabeçalho ordenável: vem de uma relação
    // um-para-muitos (as paragens da ordem) e não é ordenável no servidor.
    // Como filtro é exato, e com paginação isso é o que interessa.
    final alternadorBloqueados = _Alternador(
      ativo: _apenasBloqueados,
      icone: Icons.warning_amber_rounded,
      rotulo: 'Apenas bloqueados',
      aoTocar: () => _aplicar(() => _apenasBloqueados = !_apenasBloqueados),
    );
    final alternadorData = _Alternador(
      ativo: _dia != null,
      icone: Icons.calendar_today_outlined,
      rotulo: rotuloData,
      aoTocar: _selecionarData,
      aoLimpar: _dia == null ? null : () => _aplicar(() => _dia = null),
    );

    // Os dois alternadores têm largura própria (não encolhem); em ecrã
    // estreito não cabem ao lado da pesquisa sem estourar — passam a Wrap
    // por baixo do campo em vez de ao lado.
    if (context.ehCompacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          campoPesquisa,
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [alternadorBloqueados, alternadorData],
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: campoPesquisa),
        const SizedBox(width: 16),
        alternadorBloqueados,
        const SizedBox(width: 16),
        alternadorData,
      ],
    );
  }

  Widget _construirTabela() {
    final tabela = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            _construirCabecalho(),
            Expanded(child: _construirLinhas()),
          ],
        ),
      ),
    );

    // As 5 colunas (Expanded de largura relativa) não têm para onde encolher
    // em telemóvel — em vez de espremer o texto até ficar ilegível, a tabela
    // mantém uma largura mínima e fica dentro de scroll horizontal.
    return LayoutBuilder(
      builder: (context, constraints) {
        const larguraMinima = 700.0;
        if (constraints.maxWidth >= larguraMinima) return tabela;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: larguraMinima,
            height: constraints.maxHeight,
            child: tabela,
          ),
        );
      },
    );
  }

  Widget _construirCabecalho() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: TemasCores.fundoEcraFrio,
        border: Border(bottom: BorderSide(color: TemasCores.borda)),
      ),
      child: Row(
        children: [
          _cabecalhoOrdenavel('ID da Encomenda', OrdenacaoHistorico.codigo, 2),
          const _CabecalhoSimples(titulo: 'Produto', flex: 3),
          _cabecalhoOrdenavel('Ação / Fase', OrdenacaoHistorico.fase, 3),
          _cabecalhoOrdenavel('Data/Hora', OrdenacaoHistorico.data, 2),
          const _CabecalhoSimples(
            titulo: 'Estado',
            flex: 2,
            alinhamento: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _cabecalhoOrdenavel(
    String titulo,
    OrdenacaoHistorico coluna,
    int flex,
  ) {
    final ativa = _ordenacao == coluna;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _alternarOrdenacao(coluna),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  titulo,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: ativa
                        ? TemasCores.operadorAcentoForte
                        : TemasCores.textoSecundarioFrio,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                ativa
                    ? (_ascendente ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.swap_vert,
                size: 14,
                color:
                    ativa ? TemasCores.operadorAcentoForte : TemasCores.textoTerciario,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirLinhas() {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: TemasCores.operadorAcento),
      );
    }

    if (_erro != null && _registos.isEmpty) {
      return EstadoErro(
        titulo: 'Não foi possível carregar o histórico',
        detalhe: _erro,
        aoRepetir: _carregar,
      );
    }

    // Uma página pode não trazer nenhuma linha visível e haver mais para ler:
    // "Apenas bloqueados" é aplicado depois de o servidor responder, e podem
    // sair 50 fases sem paragem nenhuma. Sem o botão, o ecrã dizia "não há
    // registos" com páginas por percorrer — um beco sem saída.
    if (_registos.isEmpty && !_temMais) {
      return const Center(
        child: Text(
          'Nenhum registo de produção encontrado para os filtros selecionados.',
          style: TextStyle(color: TemasCores.textoTerciario),
        ),
      );
    }

    return Column(
      children: [
        // A falha de uma página adicional não pode apagar o que já está no
        // ecrã: mostra-se uma barra fina por cima da lista carregada.
        if (_erro != null)
          EstadoErro.compacto(
            titulo: 'Não foi possível carregar mais registos',
            detalhe: _erro,
            aoRepetir: _carregarMais,
          ),
        if (_registos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Text(
              'Nenhum registo nas linhas percorridas até agora. '
              'Continue a carregar para procurar mais atrás.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TemasCores.textoTerciario),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _registos.length + (_temMais ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _registos.length) return _construirCarregarMais();
              return _LinhaHistorico(registo: _registos[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _construirCarregarMais() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _aCarregarMais
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: TemasCores.operadorAcento,
                ),
              )
            : TextButton.icon(
                onPressed: _carregarMais,
                style: TextButton.styleFrom(
                  foregroundColor: TemasCores.operadorAcentoForte,
                ),
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Carregar mais'),
              ),
      ),
    );
  }
}

/// Cabeçalho de coluna sem ordenação.
class _CabecalhoSimples extends StatelessWidget {
  const _CabecalhoSimples({
    required this.titulo,
    required this.flex,
    this.alinhamento = TextAlign.start,
  });

  final String titulo;
  final int flex;
  final TextAlign alinhamento;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
        child: Text(
          titulo,
          textAlign: alinhamento,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: TemasCores.textoSecundarioFrio,
          ),
        ),
      ),
    );
  }
}

/// Botão de filtro que alterna entre ligado e desligado.
class _Alternador extends StatelessWidget {
  const _Alternador({
    required this.ativo,
    required this.icone,
    required this.rotulo,
    required this.aoTocar,
    this.aoLimpar,
  });

  final bool ativo;
  final IconData icone;
  final String rotulo;
  final VoidCallback aoTocar;
  final VoidCallback? aoLimpar;

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? TemasCores.operadorAcentoForte : TemasCores.textoSecundarioFrio;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ativo ? TemasCores.operadorAcentoForte : TemasCores.borda),
      ),
      color: ativo ? TemasCores.operadorAcentoFundo : TemasCores.superficie,
      child: InkWell(
        onTap: aoTocar,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 8),
              Text(
                rotulo,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
                  color: cor,
                ),
              ),
              if (aoLimpar != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: aoLimpar,
                  child: Icon(Icons.close, size: 16, color: cor),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma fase concluída, com as paragens que a interromperam.
class _LinhaHistorico extends StatelessWidget {
  const _LinhaHistorico({required this.registo});

  final RegistoDeTurno registo;

  @override
  Widget build(BuildContext context) {
    final motivos = registo.motivos;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: TemasCores.superficieSuave)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              registo.codigoRastreio ?? 'N/A',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: TemasCores.textoPrimario,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              registo.nomeProduto ?? 'N/A',
              style: const TextStyle(
                fontSize: 14,
                color: TemasCores.textoApoioForte,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  registo.registo.nomeFase ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    color: TemasCores.textoPrimario,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (motivos.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: TemasCores.erro,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        // A linha só tem espaço para um motivo; o tooltip dá
                        // acesso a todos, em vez de os esconder em silêncio.
                        child: Tooltip(
                          message: motivos.join('\n'),
                          child: Text(
                            motivos.length == 1
                                ? motivos.first
                                : '${motivos.first} (+${motivos.length - 1})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: TemasCores.erro,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              Formatos.dataHora(
                registo.registo.momento?.toIso8601String(),
                vazio: '-',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: TemasCores.textoSecundarioFrio,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: registo.bloqueado
                      ? TemasCores.erroFundoForte
                      : TemasCores.sucessoFundoForte,
                  borderRadius: BorderRadius.circular(20),
                ),
                // "Bloqueado"/"Concluído" com flex:1 (proporção antiga)
                // partiam a meio ("Concluíd" / "o") — a pílula não tinha
                // largura para a palavra inteira numa linha só.
                child: Text(
                  registo.bloqueado ? 'Bloqueado' : 'Concluído',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: registo.bloqueado
                        ? TemasCores.erroTextoIntenso
                        : TemasCores.sucessoTextoIntenso,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
