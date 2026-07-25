import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import '../../core/temas_cores.dart';
import '../../core/formatos.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../models/fase_model.dart';
import '../../models/historico_model.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/fluxos_repository.dart';
import '../../repositories/utilizadores_repository.dart';

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({super.key});

  @override
  State<PainelControloScreen> createState() => _PainelControloScreenState();
}

class _PainelControloScreenState extends State<PainelControloScreen> {
  final _encomendasRepo = EncomendasRepository();
  final _fluxosRepo = FluxosRepository();
  final _utilizadoresRepo = UtilizadoresRepository();
  final _searchController = TextEditingController();

  List<EncomendaModel> _encomendas = [];
  List<EncomendaModel> _encomendasFiltradas = [];
  List<Map<String, dynamic>> _reasonCodes = [];
  List<Map<String, dynamic>> _tecnicosUtilizadores = []; // Lista de técnicos/utilizadores da empresa
  Map<int, List<FaseModel>> _fasesPorProduto = {};

  String _filtroEstado = 'TODOS'; // TODOS, EM_PRODUCAO, ON_HOLD, CONCLUIDA
  bool _isLoading = true;

  /// Um único canal cobre `encomendas` e `incidencias` — antes eram dois canais
  /// separados que disparavam o mesmo recarregamento.
  RealtimeChannel? _encomendasSubscription;

  @override
  void initState() {
    super.initState();
    _carregarDados(mostrarLoader: true).then((_) => _ativarSubscricaoRealtime());
    _searchController.addListener(_filtrarEncomendas);
  }

  @override
  void dispose() {
    if (_encomendasSubscription != null) {
      _encomendasRepo.client.removeChannel(_encomendasSubscription!);
    }
    _searchController.dispose();
    super.dispose();
  }

  // --- CONSULTAS À BASE DE DADOS (SUPABASE) ---

  Future<void> _carregarDados({bool mostrarLoader = false}) async {
    try {
      if (mostrarLoader) setState(() => _isLoading = true);

      // 1. Roteiros agrupados por tipo de produto (para calcular o progresso)
      final fasesPorProduto = await _fluxosRepo.obterFasesPorProduto();

      // 2. Carrega os Reason Codes oficiais
      final reasonCodesData = await _encomendasRepo.obterReasonCodes();

      // 3. Carrega a lista de utilizadores para atribuição de Manutenção Interna
      final utilizadoresData = await _utilizadoresRepo.obterParaAtribuicao();

      // 4. Carrega as encomendas com JOINs completos (incluindo Registo Técnico de incidências)
      final encomendasData = await _encomendasRepo.obterParaPainel();

      if (mounted) {
        setState(() {
          _fasesPorProduto = fasesPorProduto;
          _reasonCodes = reasonCodesData;
          _tecnicosUtilizadores = utilizadoresData;
          _encomendas = encomendasData;
          _isLoading = false;
        });
        _filtrarEncomendas();
      }
    } catch (e) {
      _mostrarMensagem('Erro ao carregar ordens: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _ativarSubscricaoRealtime() {
    _encomendasSubscription = _encomendasRepo.escutarProducao(
      'public:encomendas_painel',
      () => _carregarDados(mostrarLoader: false),
    );
  }

  void _filtrarEncomendas() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _encomendasFiltradas = _encomendas.where((e) {
        final codigo = (e.codigoRastreio ?? '').toLowerCase();
        final cliente = (e.nomeCliente ?? '').toLowerCase();
        final matchTexto = codigo.contains(query) || cliente.contains(query);

        // O estado vem da regra única de EstadoOrdem, em vez de ser recalculado
        // aqui a partir de três colunas soltas.
        final estado = e.estado;

        if (_filtroEstado == 'CANCELADA') return matchTexto && estado == EstadoOrdem.cancelada;
        // Canceladas só aparecem no seu próprio filtro.
        if (estado == EstadoOrdem.cancelada) return false;
        if (_filtroEstado == 'EM_PRODUCAO') return matchTexto && estado == EstadoOrdem.emProducao;
        if (_filtroEstado == 'ON_HOLD') return matchTexto && estado == EstadoOrdem.emHold;
        if (_filtroEstado == 'CONCLUIDA') return matchTexto && estado == EstadoOrdem.concluida;

        return matchTexto;
      }).toList();
    });
  }

  // --- HELPER METHODS ---

  double _calcularProgresso(EncomendaModel enc) {
    if (enc.faseAtualId == null) return 1.0;

    final prodId = enc.tipoProdutoId;
    final ordemAtual = enc.ordemFaseAtual;
    if (prodId == null || ordemAtual == null) return 0.0;

    final fases = _fasesPorProduto[prodId];
    if (fases == null || fases.isEmpty) return 0.0;

    return ((ordemAtual - 1) / fases.length).clamp(0.0, 1.0);
  }

  bool _verificarSeAtrasada(DateTime? dataEntrega) {
    if (dataEntrega == null) return false;
    final hoje = DateTime.now();
    final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
    return hojeSemHoras.isAfter(dataEntrega);
  }

  // --- AVANÇAR FASE ---

  /// Avança a ordem para a fase seguinte.
  ///
  /// O registo no histórico e a atualização da encomenda correm dentro de uma
  /// única transação no servidor (`avancar_fase_encomenda`). Antes eram duas
  /// escritas independentes: se a segunda falhasse, ficava histórico órfão e a
  /// ordem presa na fase anterior.
  Future<void> _avancarFase(EncomendaModel enc) async {
    try {
      final resultado = await _encomendasRepo.avancarFase(enc.id);

      final bool concluida = resultado['concluida'] == true;
      _mostrarMensagem(concluida
          ? '🏁 Ordem de produção concluída com sucesso!'
          : 'Ordem avançada para a fase: ${resultado['proxima_fase_nome'] ?? ''}!');

      _carregarDados(mostrarLoader: false);
    } catch (e) {
      _mostrarMensagem('Erro ao avançar fase: ${_limparErro(e)}', eErro: true);
    }
  }

  /// Os repositórios já devolvem mensagens de negócio legíveis; aqui só removemos
  /// o prefixo das exceções genéricas.
  String _limparErro(Object e) {
    if (e is RepositoryException) return e.mensagem;
    return e.toString().replaceAll('Exception: ', '');
  }

  // --- AÇÕES DE WIP HOLD, REGISTO TÉCNICO HÍBRIDO E LINE CLEARANCE ---

  void _abrirDialogWipHold(EncomendaModel enc) {
    int? selectedReasonId;
    final notasController = TextEditingController();
    bool isSubmitting = false;

    final Map<int, Map<String, dynamic>> reasonCodesMap = {};
    for (var r in _reasonCodes) {
      final int rId = int.parse(r['id'].toString());
      reasonCodesMap[rId] = Map<String, dynamic>.from(r);
    }
    final listaReasonCodesUnicos = reasonCodesMap.values.toList();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.pause_circle_filled_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  const Text('Suspender Ordem (WIP Hold)'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selecione o motivo oficial (Reason Code) da paragem na linha:',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedReasonId,
                      decoration: const InputDecoration(
                        labelText: 'Reason Code *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: listaReasonCodesUnicos.map((r) {
                        final int rId = int.parse(r['id'].toString());
                        final cat = r['categoria'] ?? 'Geral';
                        final desc = r['descricao'] ?? '';
                        return DropdownMenuItem<int>(
                          value: rId,
                          child: Text('[$cat] $desc', style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: isSubmitting
                          ? null
                          : (val) => setDialogState(() => selectedReasonId = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notasController,
                      enabled: !isSubmitting,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descrição / Observações do Operador',
                        hintText: 'Ex: Frequência de ruído anormal no equipamento.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          notasController.dispose();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.block, size: 16),
                  label: const Text('Aplicar WIP Hold'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (selectedReasonId == null) {
                            _mostrarMensagem('Selecione um motivo de paragem.', eErro: true);
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          try {
                            final int encId = enc.id;

                            // Criar a incidência e suspender a ordem é uma só
                            // transação — e o posto de trabalho é resolvido no
                            // servidor a partir da fase atual.
                            await _encomendasRepo.aplicarWipHold(
                              encomendaId: encId,
                              reasonCodeId: selectedReasonId!,
                              descricaoOperador: notasController.text.trim(),
                            );

                            notasController.dispose();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🔴 Ordem colocada em ON HOLD!');
                            _carregarDados(mostrarLoader: false);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aplicar WIP Hold: ${_limparErro(e)}', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- NOVO: MODAL REGISTO TÉCNICO HÍBRIDO ---
  void _abrirDialogRegistoTecnico(EncomendaModel enc, Map<String, dynamic>? incidenciaAtiva) {
    if (incidenciaAtiva == null) return;

    String tipoManutencao = 'INTERNA'; // 'INTERNA' ou 'EXTERNA'
    String? tecnicoSelecionadoId;
    final entidadeExternaController = TextEditingController();
    final notaTecnicaController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.build_circle_rounded, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  const Text('Registo Técnico de Intervenção'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Text(
                        'Incidente: ${incidenciaAtiva['motivo'] ?? 'Manutenção Requerida'}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ),

                    const Text('Tipo de Intervenção Técnica:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 8),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'INTERNA',
                          label: Text('Manutenção Interna'),
                          icon: Icon(Icons.engineering_rounded, size: 16),
                        ),
                        ButtonSegment(
                          value: 'EXTERNA',
                          label: Text('Assistência Externa'),
                          icon: Icon(Icons.fire_truck_rounded, size: 16),
                        ),
                      ],
                      selected: {tipoManutencao},
                      onSelectionChanged: isSubmitting
                          ? null
                          : (newSelection) {
                              setDialogState(() {
                                tipoManutencao = newSelection.first;
                              });
                            },
                    ),
                    const SizedBox(height: 16),

                    if (tipoManutencao == 'INTERNA') ...[
                      DropdownButtonFormField<String>(
                        value: tecnicoSelecionadoId,
                        decoration: const InputDecoration(
                          labelText: 'Técnico Responsável *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _tecnicosUtilizadores.map((u) {
                          final id = u['utilizador_id'].toString();
                          final nome = u['nome_utilizador'] ?? 'Sem nome';
                          final perfil = u['perfil'] ?? 'Utilizador';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text('$nome ($perfil)', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: isSubmitting
                            ? null
                            : (val) => setDialogState(() => tecnicoSelecionadoId = val),
                      ),
                    ] else ...[
                      TextField(
                        controller: entidadeExternaController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(
                          labelText: 'Empresa / Entidade Externa *',
                          hintText: 'Ex: Siemens, Kuka Robotics, EletroCaldas',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),
                    TextField(
                      controller: notaTecnicaController,
                      enabled: !isSubmitting,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Relatório Técnico / Ações Corretivas',
                        hintText: 'Descreva os trabalhos efetuados, peças substituídas ou calibração efetuada...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () {
                          entidadeExternaController.dispose();
                          notaTecnicaController.dispose();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Concluir Intervenção Técnica'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (tipoManutencao == 'INTERNA' && tecnicoSelecionadoId == null) {
                            _mostrarMensagem('Selecione o técnico interno responsável.', eErro: true);
                            return;
                          }
                          if (tipoManutencao == 'EXTERNA' && entidadeExternaController.text.trim().isEmpty) {
                            _mostrarMensagem('Indique a empresa de assistência externa.', eErro: true);
                            return;
                          }

                          setDialogState(() => isSubmitting = true);

                          try {
                            final int incId = int.parse(incidenciaAtiva['id'].toString());

                            await _encomendasRepo.registarIntervencaoTecnica(
                              incidenciaId: incId,
                              tipoManutencao: tipoManutencao,
                              tecnicoId: tipoManutencao == 'INTERNA' ? tecnicoSelecionadoId : null,
                              entidadeExterna: tipoManutencao == 'EXTERNA'
                                  ? entidadeExternaController.text.trim()
                                  : null,
                              notaTecnica: notaTecnicaController.text.trim(),
                            );

                            entidadeExternaController.dispose();
                            notaTecnicaController.dispose();

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🛠️ Registo técnico concluído! A ordem aguarda agora Line Clearance.');
                            _carregarDados(mostrarLoader: false);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao gravar registo técnico: $e', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirDialogLineClearance(EncomendaModel enc, Map<String, dynamic>? incidenciaAtiva) {
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  const Text('Aprovar Line Clearance (FAI)'),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (incidenciaAtiva != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resumo da Intervenção Técnica:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.green.shade900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tipo: ${incidenciaAtiva['tipo_manutencao'] ?? 'N/A'}',
                              style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                            ),
                            if (incidenciaAtiva['tipo_manutencao'] == 'INTERNA')
                              Text(
                                'Técnico: ${incidenciaAtiva['utilizadores']?['nome_utilizador'] ?? 'Técnico Interno'}',
                                style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                              )
                            else if (incidenciaAtiva['tipo_manutencao'] == 'EXTERNA')
                              Text(
                                'Entidade: ${incidenciaAtiva['entidade_externa'] ?? 'Empresa Externa'}',
                                style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                              ),
                            if (incidenciaAtiva['nota_tecnica'] != null &&
                                incidenciaAtiva['nota_tecnica'].toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Nota Técnica: ${incidenciaAtiva['nota_tecnica']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Text('Confirmação de Qualidade:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      'Ao aprovar o Line Clearance, confirma que a 1ª peça (First Article Inspection) foi validada e a linha de produção está limpa e pronta a retomar.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Validar & Libertar Linha'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);

                          try {
                            if (incidenciaAtiva == null) {
                              throw Exception('Não há incidência ativa para validar.');
                            }

                            // Fechar a incidência e libertar a ordem numa só transação.
                            await _encomendasRepo.aprovarLineClearance(
                              int.parse(incidenciaAtiva['id'].toString()),
                            );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🟢 Line Clearance Aprovado! Produção retomada.');
                            _carregarDados(mostrarLoader: false);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aprovar Line Clearance: ${_limparErro(e)}', eErro: true);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- HISTÓRICO & TIMELINE DE RASTREABILIDADE ---

  Future<void> _abrirDialogHistorico(EncomendaModel enc) async {
    final int encId = enc.id;
    final idFormatado = Formatos.referenciaOrdem(
      encId,
      criadaEm: enc.createdAt?.toIso8601String(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.history_edu_rounded, color: Color(0xFF111625)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Histórico & Rastreabilidade - $idFormatado',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 550,
            height: 450,
            child: FutureBuilder(
              future: _encomendasRepo.obterTimeline(encId),
              builder: (context, AsyncSnapshot<TimelineOrdem> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar histórico: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  );
                }

                final timeline = snapshot.data;
                final List<Map<String, dynamic>> eventosTimeline = [];

                for (final p in timeline?.producao ?? const <HistoricoModel>[]) {
                  final data = p.momento;

                  eventosTimeline.add({
                    'timestamp': data ?? DateTime.now(),
                    'data_str': data?.toIso8601String() ?? '',
                    'titulo': 'Concluída Fase ${p.ordemFase ?? ''}: ${p.nomeFase ?? 'Fase de Produção'}',
                    'subtitulo': 'Executado por: ${p.nomeUtilizador ?? 'Operador'}',
                    'tipo': 'PRODUCAO',
                    'cor': Colors.green.shade700,
                    'icone': Icons.check_circle_rounded,
                  });
                }

                for (final inc in timeline?.incidencias ?? const <IncidenciaModel>[]) {
                  final dataRegisto = inc.inicio;
                  final motivo = inc.motivo ?? 'Incidente em Linha';
                  final notaOp = inc.descricaoOperador;

                  eventosTimeline.add({
                    'timestamp': dataRegisto ?? DateTime.now(),
                    'data_str': dataRegisto?.toIso8601String() ?? '',
                    'titulo': 'WIP Hold (Linha Suspensa)',
                    'subtitulo': 'Motivo: $motivo${notaOp != null && notaOp.isNotEmpty ? "\nNota: $notaOp" : ""}',
                    'tipo': 'HOLD',
                    'cor': Colors.red.shade700,
                    'icone': Icons.pause_circle_filled_rounded,
                  });

                  if (inc.manutencaoConcluida) {
                    final dataManut = inc.dataFimManutencao ?? dataRegisto;
                    final tipoM = inc.tipoManutencao ?? 'N/A';
                    final tecNome = inc.responsavelIntervencao ?? 'Técnico';
                    final notaTec = inc.notaTecnica ?? '';

                    eventosTimeline.add({
                      'timestamp': dataManut ?? DateTime.now(),
                      'data_str': dataManut?.toIso8601String() ?? '',
                      'titulo': 'Reparação Técnica Concluída ($tipoM)',
                      'subtitulo': 'Responsável: $tecNome${notaTec.isNotEmpty ? "\nRelatório: $notaTec" : ""}',
                      'tipo': 'MANUTENCAO',
                      'cor': Colors.amber.shade900,
                      'icone': Icons.build_circle_rounded,
                    });
                  }

                  if (inc.lineClearanceValidado && inc.dataLineClearance != null) {
                    final dataClearance = inc.dataLineClearance!;
                    eventosTimeline.add({
                      'timestamp': dataClearance,
                      'data_str': dataClearance.toIso8601String(),
                      'titulo': 'Line Clearance Aprovado (Produção Retomada)',
                      'subtitulo': 'Aprovado por Responsável de Qualidade/Supervisão',
                      'tipo': 'CLEARANCE',
                      'cor': Colors.blue.shade800,
                      'icone': Icons.verified_user_rounded,
                    });
                  }
                }

                if (eventosTimeline.isEmpty) {
                  return const Center(
                    child: Text('Nenhum evento registado no histórico desta ordem.', style: TextStyle(color: Colors.grey)),
                  );
                }

                eventosTimeline.sort((a, b) => (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime));

                return ListView.builder(
                  itemCount: eventosTimeline.length,
                  itemBuilder: (context, idx) {
                    final item = eventosTimeline[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: (item['cor'] as Color).withOpacity(0.15),
                                child: Icon(item['icone'] as IconData, size: 16, color: item['cor'] as Color),
                              ),
                              if (idx != eventosTimeline.length - 1)
                                Container(
                                  width: 2,
                                  height: 35,
                                  color: Colors.grey.shade300,
                                ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['titulo'].toString(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: item['cor'] as Color,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        Formatos.dataHora(item['data_str']),
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['subtitulo'].toString(),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  /// Cancela a ordem preservando todo o histórico de produção e incidências.
  ///
  /// Antes fazia-se `DELETE`, o que destruía a rastreabilidade da ordem — algo
  /// inaceitável num contexto fabril. Agora a ordem fica marcada como cancelada,
  /// com motivo, autor e data.
  Future<void> _cancelarOrdem(int id, String motivo) async {
    try {
      setState(() => _isLoading = true);
      await _encomendasRepo.cancelar(encomendaId: id, motivo: motivo);
      _mostrarMensagem('Ordem cancelada. O histórico foi preservado para auditoria.');
      _carregarDados(mostrarLoader: true);
    } catch (e) {
      _mostrarMensagem('Erro ao cancelar ordem: ${_limparErro(e)}', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarEdicaoOrdem(int id, String novaData, int? novaFaseId) async {
    try {
      setState(() => _isLoading = true);

      await _encomendasRepo.atualizar(
        id: id,
        dataEntrega: novaData,
        faseAtualId: novaFaseId,
      );
      _mostrarMensagem('Ordem atualizada com sucesso!');
      _carregarDados(mostrarLoader: true);
    } catch (e) {
      _mostrarMensagem('Erro ao editar ordem: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
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

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
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
                      const Text(
                        'Ordens de Produção em Curso',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 20),

                      // PESQUISA E FILTROS DE ESTADO (FIXOS NO TOPO)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Pesquisar por Código de Rastreio ou Cliente...',
                                prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                                fillColor: Colors.grey.shade100,
                                filled: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SegmentedButton<String>(
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: 'TODOS',
                                label: Text('Todas', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: 'EM_PRODUCAO',
                                label: Text('Em Produção', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.circle, color: Colors.green, size: 8),
                              ),
                              ButtonSegment(
                                value: 'ON_HOLD',
                                label: Text('ON HOLD', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.circle, color: Colors.red, size: 8),
                              ),
                              ButtonSegment(
                                value: 'CONCLUIDA',
                                label: Text('Concluídas', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.flag_rounded, size: 14),
                              ),
                              ButtonSegment(
                                value: 'CANCELADA',
                                label: Text('Canceladas', style: TextStyle(fontSize: 12)),
                                icon: Icon(Icons.block_rounded, size: 14),
                              ),
                            ],
                            selected: {_filtroEstado},
                            onSelectionChanged: (set) {
                              setState(() {
                                _filtroEstado = set.first;
                                _filtrarEncomendas();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // LISTA DE ORDENS COM SCROLL INTERNO RESTRITO
                      Expanded(
                        child: _encomendasFiltradas.isEmpty
                            ? const Center(
                                child: Text(
                                  'Não existem ordens de produção ativas correspondentes à pesquisa.',
                                  style: TextStyle(color: Colors.grey, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _encomendasFiltradas.length,
                                itemBuilder: (context, index) {
                                  return _buildOrdemCard(_encomendasFiltradas[index]);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildOrdemCard(EncomendaModel enc) {
    final idFormatado = Formatos.referenciaOrdem(
      enc.id,
      criadaEm: enc.createdAt?.toIso8601String(),
    );
    final String codigoRastreio = enc.codigoRastreio ?? 'N/A';
    final String nomeCliente = enc.nomeCliente ?? 'N/A';
    final String nomeProduto = enc.nomeProduto ?? 'N/A';
    final String prioridade = enc.prioridade;

    final estado = enc.estado;
    final bool cancelada = estado == EstadoOrdem.cancelada;
    final bool emHold = estado == EstadoOrdem.emHold;
    final bool concluida = estado == EstadoOrdem.concluida;

    final String faseNome = concluida
        ? 'Produção Concluída'
        : (enc.nomeFaseAtual != null
            ? 'Fase ${enc.ordemFaseAtual}: ${enc.nomeFaseAtual}'
            : 'Aguardando Início');
    final String postoTrabalho = enc.postoFaseAtual ?? 'Linha Geral';
    final String dataEntrega = enc.dataEntregaIso ?? '';

    final double progresso = _calcularProgresso(enc);
    final int progressoPercentagem = (progresso * 100).toInt();
    final bool atrasada = _verificarSeAtrasada(enc.dataEntrega);

    // Incidência ativa: o modelo aplica a regra (sem line clearance validado)
    final Map<String, dynamic>? incidenciaAtiva = enc.incidenciaAtiva;
    final bool manutencaoConcluida = incidenciaAtiva?['manutencao_concluida'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: emHold ? Colors.red.shade300 : Colors.grey.shade200, width: emHold ? 2 : 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            idFormatado,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              codigoRastreio,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                          ),

                          // BADGE DE ESTADO
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cancelada
                                  ? Colors.grey.shade200
                                  : (emHold ? Colors.red.shade50 : (concluida ? Colors.green.shade50 : Colors.blue.shade50)),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: cancelada
                                    ? Colors.grey.shade400
                                    : (emHold ? Colors.red.shade300 : (concluida ? Colors.green.shade300 : Colors.blue.shade300)),
                              ),
                            ),
                            child: Text(
                              cancelada
                                  ? 'CANCELADA'
                                  : (emHold ? 'ON HOLD' : (concluida ? 'CONCLUÍDA' : 'EM PRODUÇÃO')),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cancelada
                                    ? Colors.grey.shade700
                                    : (emHold ? Colors.red.shade800 : (concluida ? Colors.green.shade800 : Colors.blue.shade800)),
                              ),
                            ),
                          ),

                          if (atrasada)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                'Atrasada',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                              ),
                            ),

                          if (prioridade != 'Normal')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text(
                                prioridade.toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(nomeCliente, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                      Text(nomeProduto, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Text('Fase Atual: ', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                          Text(faseNome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                          if (!concluida) ...[
                            const SizedBox(width: 8),
                            Chip(
                              label: Text(postoTrabalho, style: const TextStyle(fontSize: 10)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          dataEntrega,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // BOTÕES CONDICIONAIS DE WIP HOLD / REGISTO TÉCNICO / LINE CLEARANCE
                        // (uma ordem cancelada só permite consultar o histórico)
                        if (cancelada) ...[
                          // sem ações operacionais
                        ] else if (emHold) ...[
                          if (!manutencaoConcluida)
                            ElevatedButton.icon(
                              onPressed: () => _abrirDialogRegistoTecnico(enc, incidenciaAtiva),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              icon: const Icon(Icons.build_rounded, size: 14),
                              label: const Text('Registo Técnico', style: TextStyle(fontSize: 12)),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: () => _abrirDialogLineClearance(enc, incidenciaAtiva),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                              icon: const Icon(Icons.verified_user_rounded, size: 14),
                              label: const Text('Line Clearance', style: TextStyle(fontSize: 12)),
                            ),
                          const SizedBox(width: 8),
                        ] else if (!concluida) ...[
                          OutlinedButton.icon(
                            onPressed: () => _abrirDialogWipHold(enc),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade300),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            icon: const Icon(Icons.pause, size: 14),
                            label: const Text('WIP Hold', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => _avancarFase(enc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF111625),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            icon: const Icon(Icons.skip_next_rounded, size: 14),
                            label: const Text('Avançar Fase', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                        ],

                        OutlinedButton.icon(
                          onPressed: () => _abrirDialogHistorico(enc),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          icon: const Icon(Icons.history_rounded, size: 14, color: Colors.blueGrey),
                          label: const Text('Histórico', style: TextStyle(color: Colors.black87, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),

                        if (!cancelada) ...[
                          OutlinedButton.icon(
                            onPressed: () => _abrirDialogEditar(enc),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.black87),
                            label: const Text('Editar', style: TextStyle(color: Colors.black87, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => _confirmarCancelamento(enc.id, idFormatado),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.black87),
                            label: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$progressoPercentagem% concluído',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    )
                  ],
                ),
              ],
            ),
          ),

          // MOTIVO DO CANCELAMENTO (rasto de auditoria)
          if (cancelada) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.block_rounded, color: Colors.grey.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ORDEM CANCELADA em ${Formatos.dataHora(enc.dataCancelamento?.toIso8601String())} — '
                      '${enc.motivoCancelamento ?? 'sem motivo registado'}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // BANNER ALERTA DE INCIDÊNCIA ATIVA / ESTADO DA REPARAÇÃO
          if (emHold && incidenciaAtiva != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
              decoration: BoxDecoration(
                color: manutencaoConcluida ? Colors.green.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: manutencaoConcluida ? Colors.green.shade300 : Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    manutencaoConcluida ? Icons.build_circle_rounded : Icons.warning_rounded,
                    color: manutencaoConcluida ? Colors.green.shade800 : Colors.amber.shade900,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          manutencaoConcluida
                              ? 'REPARAÇÃO TÉCNICA CONCLUÍDA — AGUARDA LINE CLEARANCE (QUALIDADE)'
                              : 'BLOQUEIO EM LINHA: ${incidenciaAtiva['motivo'] ?? 'Manutenção Pendente'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: manutencaoConcluida ? Colors.green.shade900 : Colors.amber.shade900,
                          ),
                        ),
                        if (incidenciaAtiva['descricao_operador'] != null &&
                            incidenciaAtiva['descricao_operador'].toString().isNotEmpty)
                          Text(
                            'Nota Operador: ${incidenciaAtiva['descricao_operador']}',
                            style: TextStyle(
                              fontSize: 11,
                              color: manutencaoConcluida ? Colors.green.shade800 : Colors.amber.shade800,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          ClipRRect(
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 6,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(
                emHold ? Colors.red : (concluida ? Colors.green : const Color(0xFF111625)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- POPUPS E DIALOGS ADICIONAIS ---

  void _confirmarCancelamento(int id, String refOrdem) {
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Cancelar Ordem de Produção'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A ordem $refOrdem será marcada como cancelada. O histórico de '
                      'produção e as incidências são preservados para auditoria.',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: motivoController,
                      maxLines: 2,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Motivo do cancelamento *',
                        hintText: 'Ex: Anulação a pedido do cliente.',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    motivoController.dispose();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Não'),
                ),
                ElevatedButton(
                  onPressed: motivoController.text.trim().isEmpty
                      ? null
                      : () {
                          final motivo = motivoController.text.trim();
                          motivoController.dispose();
                          Navigator.pop(dialogContext);
                          _cancelarOrdem(id, motivo);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('Sim, Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _abrirDialogEditar(EncomendaModel enc) {
    final dataController = TextEditingController(text: enc.dataEntregaIso ?? '');
    final fasesDisponiveis = List<FaseModel>.from(
      _fasesPorProduto[enc.tipoProdutoId] ?? const <FaseModel>[],
    );

    int? faseIdSelecionada = enc.faseAtualId;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editar Ordem de Produção'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dataController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Data de Entrega (AAAA-MM-DD)',
                      suffixIcon: Icon(Icons.calendar_today),
                    ),
                    onTap: () async {
                      final DateTime? data = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(dataController.text) ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (data != null) {
                        setDialogState(() {
                          dataController.text =
                              "${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}";
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: faseIdSelecionada,
                    decoration: const InputDecoration(labelText: 'Fase Atual de Produção'),
                    items: [
                      ...fasesDisponiveis.map((f) {
                        return DropdownMenuItem<int?>(
                          value: f.id,
                          child: Text('Fase ${f.ordem}: ${f.nomeFasePadrao}'),
                        );
                      }),
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('🏁 Dar como Concluída'),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => faseIdSelecionada = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dataController.dispose();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final novaData = dataController.text.trim();
                    dataController.dispose();
                    Navigator.pop(dialogContext);
                    _salvarEdicaoOrdem(
                      enc.id,
                      novaData,
                      faseIdSelecionada,
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
}