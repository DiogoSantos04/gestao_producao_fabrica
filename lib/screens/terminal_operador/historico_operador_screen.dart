import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoricoOperadorScreen extends StatefulWidget {
  const HistoricoOperadorScreen({super.key});

  @override
  State<HistoricoOperadorScreen> createState() => _HistoricoOperadorScreenState();
}

class _HistoricoOperadorScreenState extends State<HistoricoOperadorScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  
  List<dynamic> _historicoCompleto = [];
  List<dynamic> _historicoFiltrado = [];
  bool _isLoading = true;

  // Variáveis de controlo para ordenação e filtro por data
  String _colunaOrdenacao = 'data'; // 'codigo', 'produto', 'fase', 'data', 'estado'
  bool _ordenacaoAscendente = false; // Padrão: mais recentes primeiro
  DateTime? _dataSelecionada; // Filtro de data específica

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
    _searchController.addListener(_filtrarEReordenarResultados);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarHistorico() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        // Mesmo defeito que existia nos relatórios: o `return` seco deixava
        // `_isLoading = true` e o ecrã num spinner infinito.
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final data = await _supabase
          .from('historico_producao')
          .select('''
            id,
            data_conclusao,
            encomendas!encomenda_id (
              codigo_rastreio,
              tipos_produto!tipos_produtos_id (
                nome_tipo_produto
              )
            ),
            fases_padrao!fase_concluida_id (
              nome_fase_padrao
            ),
            incidencias (
              id,
              motivo
            )
          ''')
          .eq('utilizador_id', user.id)
          .order('data_conclusao', ascending: false);

      if (mounted) {
        setState(() {
          _historicoCompleto = data;
          // `_calcular...` é puro: chamar aqui `_filtrarEReordenarResultados()`
          // — que faz `setState` — punha um `setState` dentro de outro.
          _historicoFiltrado = _calcularResultadoFiltrado();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico de produção: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selecionarData(BuildContext context) async {
    final DateTime? dataPick = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2563EB),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataPick != null) {
      setState(() {
        _dataSelecionada = dataPick;
        _historicoFiltrado = _calcularResultadoFiltrado();
      });
    }
  }

  void _limparFiltroData() {
    setState(() {
      _dataSelecionada = null;
      _historicoFiltrado = _calcularResultadoFiltrado();
    });
  }

  void _alternarOrdenacao(String coluna) {
    setState(() {
      if (_colunaOrdenacao == coluna) {
        _ordenacaoAscendente = !_ordenacaoAscendente;
      } else {
        _colunaOrdenacao = coluna;
        _ordenacaoAscendente = true;
      }
      _historicoFiltrado = _calcularResultadoFiltrado();
    });
  }

  /// Ouvinte do campo de pesquisa: aplica o resultado ao estado.
  ///
  /// O cálculo vive em [_calcularResultadoFiltrado], que é puro, para que os
  /// callers que já estão dentro de um `setState` (carregamento, filtro de
  /// data, ordenação) o possam usar sem aninhar um segundo `setState`.
  void _filtrarEReordenarResultados() {
    if (!mounted) return;
    setState(() {
      _historicoFiltrado = _calcularResultadoFiltrado();
    });
  }

  List<dynamic> _calcularResultadoFiltrado() {
    final query = _searchController.text.trim().toLowerCase();
    
    // 1. Filtragem por Texto e por Data Específica
    List<dynamic> resultado = _historicoCompleto.where((registo) {
      // Filtro por Texto (Código de Rastreio)
      bool bateTexto = query.isEmpty ||
          (registo['encomendas']?['codigo_rastreio']?.toString().toLowerCase().contains(query) ?? false);

      // Filtro por Data
      bool bateData = true;
      if (_dataSelecionada != null) {
        final String? dtStr = registo['data_conclusao'];
        if (dtStr != null) {
          // `toLocal()`: o registo vem em UTC e `_dataSelecionada` é uma data
          // local escolhida no calendário. Sem conversão, o trabalho de fim de
          // turno era atribuído ao dia seguinte.
          final dt = DateTime.tryParse(dtStr)?.toLocal();
          if (dt != null) {
            bateData = dt.year == _dataSelecionada!.year &&
                       dt.month == _dataSelecionada!.month &&
                       dt.day == _dataSelecionada!.day;
          } else {
            bateData = false;
          }
        } else {
          bateData = false;
        }
      }

      return bateTexto && bateData;
    }).toList();

    // 2. Ordenação Dinâmica por Coluna
    resultado.sort((a, b) {
      int comparacao = 0;

      switch (_colunaOrdenacao) {
        case 'codigo':
          final codA = a['encomendas']?['codigo_rastreio']?.toString().toLowerCase() ?? '';
          final codB = b['encomendas']?['codigo_rastreio']?.toString().toLowerCase() ?? '';
          comparacao = codA.compareTo(codB);
          break;

        case 'produto':
          final prodA = a['encomendas']?['tipos_produto']?['nome_tipo_produto']?.toString().toLowerCase() ?? '';
          final prodB = b['encomendas']?['tipos_produto']?['nome_tipo_produto']?.toString().toLowerCase() ?? '';
          comparacao = prodA.compareTo(prodB);
          break;

        case 'fase':
          final faseA = a['fases_padrao']?['nome_fase_padrao']?.toString().toLowerCase() ?? '';
          final faseB = b['fases_padrao']?['nome_fase_padrao']?.toString().toLowerCase() ?? '';
          comparacao = faseA.compareTo(faseB);
          break;

        case 'data':
          final dtA = DateTime.tryParse(a['data_conclusao'] ?? '') ?? DateTime(1970);
          final dtB = DateTime.tryParse(b['data_conclusao'] ?? '') ?? DateTime(1970);
          comparacao = dtA.compareTo(dtB);
          break;

        case 'estado':
          final isBloqA = (a['incidencias'] as List? ?? []).isNotEmpty ? 1 : 0;
          final isBloqB = (b['incidencias'] as List? ?? []).isNotEmpty ? 1 : 0;
          comparacao = isBloqA.compareTo(isBloqB);
          break;
      }

      return _ordenacaoAscendente ? comparacao : -comparacao;
    });

    return resultado;
  }

  String _formatarData(String? isoString) {
    if (isoString == null) return '-';
    // `timestamptz` chega em UTC; sem `toLocal()` a hora mostrada ao operador
    // não é a hora do turno.
    final dt = DateTime.tryParse(isoString)?.toLocal();
    if (dt == null) return '-';
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final ano = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final minuto = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$ano $hora:$minuto';
  }

  Widget _construirCabecalhoOrdenavel({
    required String titulo,
    required String chaveColuna,
    required int flex,
    TextAlign alignment = TextAlign.start,
  }) {
    final bool estaAtiva = _colunaOrdenacao == chaveColuna;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _alternarOrdenacao(chaveColuna),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
          child: Row(
            mainAxisAlignment: alignment == TextAlign.center
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  titulo,
                  textAlign: alignment,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: estaAtiva ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                estaAtiva
                    ? (_ordenacaoAscendente ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.swap_vert,
                size: 14,
                color: estaAtiva ? const Color(0xFF2563EB) : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String labelData = _dataSelecionada != null
        ? '${_dataSelecionada!.day.toString().padLeft(2, '0')}/${_dataSelecionada!.month.toString().padLeft(2, '0')}/${_dataSelecionada!.year}'
        : 'Filtrar por Data';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Histórico de Produção',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Consulte suas tarefas concluídas ou bloqueios registados',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Barra de Filtros (Pesquisa por Texto + Filtro por Data)
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Pesquisar por ID...',
                                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                border: InputBorder.none,
                                icon: const Icon(Icons.search, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Botão de Seleção de Data
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _dataSelecionada != null ? const Color(0xFF2563EB) : Colors.grey.shade200,
                          ),
                        ),
                        color: _dataSelecionada != null ? const Color(0xFFEFF6FF) : Colors.white,
                        child: InkWell(
                          onTap: () => _selecionarData(context),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 18,
                                  color: _dataSelecionada != null ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  labelData,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: _dataSelecionada != null ? FontWeight.bold : FontWeight.normal,
                                    color: _dataSelecionada != null ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                  ),
                                ),
                                if (_dataSelecionada != null) ...[
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _limparFiltroData,
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      color: Colors.white,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            // Cabeçalho da Tabela com Botões de Ordenação
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(color: Colors.grey.shade200),
                                ),
                              ),
                              child: Row(
                                children: [
                                  _construirCabecalhoOrdenavel(
                                    titulo: 'ID da Encomenda',
                                    chaveColuna: 'codigo',
                                    flex: 2,
                                  ),
                                  _construirCabecalhoOrdenavel(
                                    titulo: 'Produto',
                                    chaveColuna: 'produto',
                                    flex: 3,
                                  ),
                                  _construirCabecalhoOrdenavel(
                                    titulo: 'Ação / Fase',
                                    chaveColuna: 'fase',
                                    flex: 3,
                                  ),
                                  _construirCabecalhoOrdenavel(
                                    titulo: 'Data/Hora',
                                    chaveColuna: 'data',
                                    flex: 2,
                                  ),
                                  _construirCabecalhoOrdenavel(
                                    titulo: 'Estado',
                                    chaveColuna: 'estado',
                                    flex: 1,
                                    alignment: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                            Expanded(
                              child: _historicoFiltrado.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Nenhum registo de produção encontrado para os filtros selecionados.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _historicoFiltrado.length,
                                      itemBuilder: (context, index) {
                                        final item = _historicoFiltrado[index];
                                        final codigo = item['encomendas']?['codigo_rastreio'] ?? 'N/A';
                                        final produto = item['encomendas']?['tipos_produto']?['nome_tipo_produto'] ?? 'N/A';
                                        final fase = item['fases_padrao']?['nome_fase_padrao'] ?? 'N/A';
                                        final dataConclusao = _formatarData(item['data_conclusao']);

                                        final List<dynamic> incidencias = item['incidencias'] ?? [];
                                        final bool isBloqueado = incidencias.isNotEmpty;

                                        // Uma fase pode ter sido bloqueada mais
                                        // do que uma vez. `incidencias.first`
                                        // mostrava só a primeira e escondia as
                                        // restantes sem qualquer indicação.
                                        final List<String> motivosBloqueio = incidencias
                                            .map((i) => (i['motivo'] as String?)?.trim())
                                            .whereType<String>()
                                            .where((m) => m.isNotEmpty)
                                            .toList();
                                        final String? motivoBloqueio = motivosBloqueio.isEmpty
                                            ? null
                                            : (motivosBloqueio.length == 1
                                                ? motivosBloqueio.first
                                                : '${motivosBloqueio.first} (+${motivosBloqueio.length - 1})');

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  codigo,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  produto,
                                                  style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      fase,
                                                      style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
                                                    ),
                                                    if (isBloqueado && motivoBloqueio != null) ...[
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                                                          const SizedBox(width: 4),
                                                          Expanded(
                                                            // A linha só tem
                                                            // espaço para um
                                                            // motivo; o tooltip
                                                            // dá acesso a todos.
                                                            child: Tooltip(
                                                              message: motivosBloqueio.join('\n'),
                                                              child: Text(
                                                                motivoBloqueio,
                                                                maxLines: 1,
                                                                overflow: TextOverflow.ellipsis,
                                                                style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors.red,
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ]
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  dataConclusao,
                                                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: isBloqueado 
                                                          ? const Color(0xFFFEE2E2)
                                                          : const Color(0xFFD1FAE5),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Text(
                                                      isBloqueado ? 'Bloqueado' : 'Concluído',
                                                      style: TextStyle(
                                                        color: isBloqueado 
                                                            ? const Color(0xFF991B1B)
                                                            : const Color(0xFF065F46),
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
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}