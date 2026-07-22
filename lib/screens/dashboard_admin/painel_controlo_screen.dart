import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class PainelControloScreen extends StatefulWidget {
  const PainelControloScreen({super.key});

  @override
  State<PainelControloScreen> createState() => _PainelControloScreenState();
}

class _PainelControloScreenState extends State<PainelControloScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<dynamic> _encomendas = [];
  List<dynamic> _encomendasFiltradas = [];
  List<dynamic> _reasonCodes = [];
  List<dynamic> _tecnicosUtilizadores = []; // Lista de técnicos/utilizadores da empresa
  Map<int, List<dynamic>> _fasesPorProduto = {};

  String _filtroEstado = 'TODOS'; // TODOS, EM_PRODUCAO, ON_HOLD, CONCLUIDA
  bool _isLoading = true;

  RealtimeChannel? _encomendasSubscription;
  RealtimeChannel? _incidenciasSubscription;

  @override
  void initState() {
    super.initState();
    _carregarDados(mostrarLoader: true).then((_) => _ativarSubscricaoRealtime());
    _searchController.addListener(_filtrarEncomendas);
  }

  @override
  void dispose() {
    if (_encomendasSubscription != null) {
      _supabase.removeChannel(_encomendasSubscription!);
    }
    if (_incidenciasSubscription != null) {
      _supabase.removeChannel(_incidenciasSubscription!);
    }
    _searchController.dispose();
    super.dispose();
  }

  // --- CONSULTAS À BASE DE DADOS (SUPABASE) ---

  Future<void> _carregarDados({bool mostrarLoader = false}) async {
    try {
      if (mostrarLoader) setState(() => _isLoading = true);

      // 1. Carrega todas as fases padrão ordenadas
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id, nome_fase_padrao, posto_trabalho')
          .order('ordem');

      final Map<int, List<dynamic>> tempFasesPorProduto = {};
      for (var f in fasesData) {
        final prodId = f['tipos_produto_id'] as int;
        tempFasesPorProduto.putIfAbsent(prodId, () => []).add(f);
      }

      // 2. Carrega os Reason Codes oficiais
      final reasonCodesData = await _supabase
          .from('reason_codes')
          .select()
          .order('categoria');

      // 3. Carrega a lista de utilizadores para atribuição de Manutenção Interna
      final utilizadoresData = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, perfil')
          .order('nome_utilizador');

      // 4. Carrega as encomendas com JOINs completos (incluindo Registo Técnico de incidências)
      final encomendasData = await _supabase.from('encomendas').select('''
        *,
        clientes (nome_cliente),
        tipos_produto:tipos_produtos_id (nome_tipo_produto),
        fase_atual:fase_atual_id (id, nome_fase_padrao, ordem, posto_trabalho),
        incidencias (
          id,
          motivo,
          descricao_operador,
          tipo_manutencao,
          tecnico_id,
          entidade_externa,
          nota_tecnica,
          manutencao_concluida,
          data_fim_manutencao,
          line_clearance_validado,
          estado,
          data_registo,
          utilizadores:tecnico_id (nome_utilizador),
          reason_codes (categoria, descricao)
        )
      ''').order('id', ascending: false);

      if (mounted) {
        setState(() {
          _fasesPorProduto = tempFasesPorProduto;
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
    _encomendasSubscription = _supabase
        .channel('public:encomendas_painel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encomendas',
          callback: (payload) => _carregarDados(mostrarLoader: false),
        )
        .subscribe();

    _incidenciasSubscription = _supabase
        .channel('public:incidencias_painel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidencias',
          callback: (payload) => _carregarDados(mostrarLoader: false),
        )
        .subscribe();
  }

  void _filtrarEncomendas() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _encomendasFiltradas = _encomendas.where((e) {
        final codigo = (e['codigo_rastreio'] ?? e['codigo_encomenda'] ?? '').toString().toLowerCase();
        final cliente = (e['clientes'] != null ? e['clientes']['nome_cliente'] : '').toString().toLowerCase();
        final matchTexto = codigo.contains(query) || cliente.contains(query);

        final bool emHold = e['em_suspenso'] == true;
        final bool concluida = e['fase_atual_id'] == null;

        if (_filtroEstado == 'EM_PRODUCAO') return matchTexto && !emHold && !concluida;
        if (_filtroEstado == 'ON_HOLD') return matchTexto && emHold;
        if (_filtroEstado == 'CONCLUIDA') return matchTexto && concluida;

        return matchTexto;
      }).toList();
    });
  }

  // --- HELPER METHODS ---

  double _calcularProgresso(Map<String, dynamic> enc) {
    if (enc['fase_atual_id'] == null) return 1.0;

    final int? prodId = enc['tipos_produtos_id'] as int?;
    final faseAtual = enc['fase_atual'];

    if (prodId == null || faseAtual == null) return 0.0;

    final fases = _fasesPorProduto[prodId];
    if (fases == null || fases.isEmpty) return 0.0;

    final int ordemAtual = faseAtual['ordem'] as int? ?? 1;
    final int totalFases = fases.length;

    return ((ordemAtual - 1) / totalFases).clamp(0.0, 1.0);
  }

  bool _verificarSeAtrasada(String? dataEntregaStr) {
    if (dataEntregaStr == null || dataEntregaStr.isEmpty) return false;
    try {
      final dataEntrega = DateTime.parse(dataEntregaStr);
      final hoje = DateTime.now();
      final hojeSemHoras = DateTime(hoje.year, hoje.month, hoje.day);
      return hojeSemHoras.isAfter(dataEntrega);
    } catch (_) {
      return false;
    }
  }

  String _formatarDataHora(String? isoStr) {
    if (isoStr == null || isoStr.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      final dia = dt.day.toString().padLeft(2, '0');
      final mes = dt.month.toString().padLeft(2, '0');
      final ano = dt.year;
      final hora = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$dia/$mes/$ano às $hora:$min';
    } catch (_) {
      return isoStr;
    }
  }

  // --- AVANÇAR FASE ---

  Future<void> _avancarFase(Map<String, dynamic> enc) async {
    try {
      final int prodId = enc['tipos_produtos_id'];
      final int? faseAtualId = enc['fase_atual_id'];

      if (faseAtualId == null) return;

      final user = _supabase.auth.currentUser;

      await _supabase.from('historico_producao').insert({
        'encomenda_id': enc['id'],
        'fase_concluida_id': faseAtualId,
        'utilizador_id': user?.id,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      final fasesDoProduto = List<dynamic>.from(_fasesPorProduto[prodId] ?? []);
      fasesDoProduto.sort((a, b) => (a['ordem'] as int).compareTo(b['ordem'] as int));

      final indexAtual = fasesDoProduto.indexWhere((f) => f['id'] == faseAtualId);

      if (indexAtual != -1 && indexAtual + 1 < fasesDoProduto.length) {
        final proximaFase = fasesDoProduto[indexAtual + 1];
        await _supabase.from('encomendas').update({
          'fase_atual_id': proximaFase['id'],
        }).eq('id', enc['id']);

        _mostrarMensagem('Ordem avançada para a fase: ${proximaFase['nome_fase_padrao']}!');
      } else {
        await _supabase.from('encomendas').update({
          'fase_atual_id': null,
        }).eq('id', enc['id']);

        _mostrarMensagem('🏁 Ordem de produção concluída com sucesso!');
      }

      _carregarDados(mostrarLoader: false);
    } catch (e) {
      _mostrarMensagem('Erro ao avançar fase: $e', eErro: true);
    }
  }

  // --- AÇÕES DE WIP HOLD, REGISTO TÉCNICO HÍBRIDO E LINE CLEARANCE ---

  void _abrirDialogWipHold(Map<String, dynamic> enc) {
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
                            final int encId = int.parse(enc['id'].toString());
                            final reasonObjeto = reasonCodesMap[selectedReasonId];

                            final String cat = reasonObjeto?['categoria'] ?? 'Geral';
                            final String desc = reasonObjeto?['descricao'] ?? '';

                            await _supabase.from('incidencias').insert({
                              'encomenda_id': encId,
                              'reason_code_id': selectedReasonId,
                              'motivo': '[$cat] $desc',
                              'descricao_operador': notasController.text.trim(),
                              'data_registo': DateTime.now().toIso8601String(),
                              'manutencao_concluida': false,
                              'line_clearance_validado': false,
                              'estado': 'PENDENTE',
                            });

                            await _supabase.from('encomendas').update({
                              'em_suspenso': true,
                            }).eq('id', encId);

                            notasController.dispose();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🔴 Ordem colocada em ON HOLD!');
                            _carregarDados(mostrarLoader: false);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aplicar WIP Hold: $e', eErro: true);
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
  void _abrirDialogRegistoTecnico(Map<String, dynamic> enc, Map<String, dynamic>? incidenciaAtiva) {
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

                            await _supabase.from('incidencias').update({
                              'tipo_manutencao': tipoManutencao,
                              'tecnico_id': tipoManutencao == 'INTERNA' ? tecnicoSelecionadoId : null,
                              'entidade_externa': tipoManutencao == 'EXTERNA' ? entidadeExternaController.text.trim() : null,
                              'nota_tecnica': notaTecnicaController.text.trim(),
                              'manutencao_concluida': true,
                              'data_fim_manutencao': DateTime.now().toIso8601String(),
                            }).eq('id', incId);

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

  void _abrirDialogLineClearance(Map<String, dynamic> enc, Map<String, dynamic>? incidenciaAtiva) {
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
                            final user = _supabase.auth.currentUser;
                            final int encId = int.parse(enc['id'].toString());

                            if (incidenciaAtiva != null) {
                              final int incId = int.parse(incidenciaAtiva['id'].toString());
                              await _supabase.from('incidencias').update({
                                'line_clearance_validado': true,
                                'line_clearance_por': user?.id,
                                'data_line_clearance': DateTime.now().toIso8601String(),
                                'estado': 'RESOLVIDO',
                              }).eq('id', incId);
                            }

                            await _supabase.from('encomendas').update({
                              'em_suspenso': false,
                            }).eq('id', encId);

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }

                            _mostrarMensagem('🟢 Line Clearance Aprovado! Produção retomada.');
                            _carregarDados(mostrarLoader: false);
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            _mostrarMensagem('Erro ao aprovar Line Clearance: $e', eErro: true);
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

  Future<void> _abrirDialogHistorico(Map<String, dynamic> enc) async {
    final int encId = int.parse(enc['id'].toString());
    final idFormatado = 'ORD-2026-${encId.toString().padLeft(3, '0')}';

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
              future: Future.wait([
                _supabase.from('historico_producao').select('''
                  *,
                  fases_padrao:fase_concluida_id (nome_fase_padrao, ordem),
                  utilizadores:utilizador_id (nome_utilizador)
                ''').eq('encomenda_id', encId),
                _supabase.from('incidencias').select('''
                  *,
                  reason_codes:reason_code_id (categoria, descricao),
                  utilizadores:tecnico_id (nome_utilizador)
                ''').eq('encomenda_id', encId),
              ]),
              builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar histórico: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  );
                }

                final List<dynamic> producaoList = snapshot.data?[0] ?? [];
                final List<dynamic> incidenciasList = snapshot.data?[1] ?? [];

                final List<Map<String, dynamic>> eventosTimeline = [];

                for (var p in producaoList) {
                  final fase = p['fases_padrao'];
                  final user = p['utilizadores'];
                  final data = p['data_conclusao'] ?? p['created_at'];

                  eventosTimeline.add({
                    'timestamp': DateTime.tryParse(data.toString()) ?? DateTime.now(),
                    'data_str': data.toString(),
                    'titulo': 'Concluída Fase ${fase?['ordem'] ?? ''}: ${fase?['nome_fase_padrao'] ?? 'Fase de Produção'}',
                    'subtitulo': 'Executado por: ${user?['nome_utilizador'] ?? 'Operador'}',
                    'tipo': 'PRODUCAO',
                    'cor': Colors.green.shade700,
                    'icone': Icons.check_circle_rounded,
                  });
                }

                for (var inc in incidenciasList) {
                  final dataRegisto = inc['data_registo'] ?? inc['created_at'];
                  final motivo = inc['motivo'] ?? 'Incidente em Linha';
                  final notaOp = inc['descricao_operador'];

                  eventosTimeline.add({
                    'timestamp': DateTime.tryParse(dataRegisto.toString()) ?? DateTime.now(),
                    'data_str': dataRegisto.toString(),
                    'titulo': 'WIP Hold (Linha Suspensa)',
                    'subtitulo': 'Motivo: $motivo${notaOp != null && notaOp.toString().isNotEmpty ? "\nNota: $notaOp" : ""}',
                    'tipo': 'HOLD',
                    'cor': Colors.red.shade700,
                    'icone': Icons.pause_circle_filled_rounded,
                  });

                  if (inc['manutencao_concluida'] == true) {
                    final dataManut = inc['data_fim_manutencao'] ?? dataRegisto;
                    final tipoM = inc['tipo_manutencao'] ?? 'N/A';
                    final tecNome = inc['utilizadores']?['nome_utilizador'] ?? inc['entidade_externa'] ?? 'Técnico';
                    final notaTec = inc['nota_tecnica'] ?? '';

                    eventosTimeline.add({
                      'timestamp': DateTime.tryParse(dataManut.toString()) ?? DateTime.now(),
                      'data_str': dataManut.toString(),
                      'titulo': 'Reparação Técnica Concluída ($tipoM)',
                      'subtitulo': 'Responsável: $tecNome${notaTec.isNotEmpty ? "\nRelatório: $notaTec" : ""}',
                      'tipo': 'MANUTENCAO',
                      'cor': Colors.amber.shade900,
                      'icone': Icons.build_circle_rounded,
                    });
                  }

                  if (inc['line_clearance_validado'] == true && inc['data_line_clearance'] != null) {
                    final dataClearance = inc['data_line_clearance'];
                    eventosTimeline.add({
                      'timestamp': DateTime.tryParse(dataClearance.toString()) ?? DateTime.now(),
                      'data_str': dataClearance.toString(),
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
                                        _formatarDataHora(item['data_str'].toString()),
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

  Future<void> _cancelarOrdem(int id) async {
    try {
      setState(() => _isLoading = true);
      await _supabase.from('encomendas').delete().eq('id', id);
      _mostrarMensagem('Ordem de produção cancelada e removida com sucesso!');
      _carregarDados(mostrarLoader: true);
    } catch (e) {
      _mostrarMensagem('Erro ao cancelar ordem: $e', eErro: true);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarEdicaoOrdem(int id, String novaData, int? novaFaseId) async {
    try {
      setState(() => _isLoading = true);

      final dadosAtualizacao = {
        'data_entrega': novaData,
        'fase_atual_id': novaFaseId,
      };

      await _supabase.from('encomendas').update(dadosAtualizacao).eq('id', id);
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

  Widget _buildOrdemCard(Map<String, dynamic> enc) {
    final idFormatado = 'ORD-2026-${enc['id'].toString().padLeft(3, '0')}';
    final String codigoRastreio = enc['codigo_rastreio'] ?? 'N/A';
    final String nomeCliente = enc['clientes'] != null ? enc['clientes']['nome_cliente'] : 'N/A';
    final String nomeProduto = enc['tipos_produto'] != null ? enc['tipos_produto']['nome_tipo_produto'] : 'N/A';
    final String prioridade = enc['prioridade'] ?? 'Normal';

    final bool emHold = enc['em_suspenso'] == true;
    final bool concluida = enc['fase_atual_id'] == null;

    final faseAtual = enc['fase_atual'];
    final String faseNome = concluida
        ? 'Produção Concluída'
        : (faseAtual != null
            ? 'Fase ${faseAtual['ordem']}: ${faseAtual['nome_fase_padrao']}'
            : 'Aguardando Início');
    final String postoTrabalho = faseAtual?['posto_trabalho'] ?? 'Linha Geral';
    final String dataEntrega = enc['data_entrega'] ?? '';

    final double progresso = _calcularProgresso(enc);
    final int progressoPercentagem = (progresso * 100).toInt();
    final bool atrasada = _verificarSeAtrasada(dataEntrega);

    // Identificar incidência ativa pendente
    final List<dynamic> incidenciasList = enc['incidencias'] ?? [];
    final Map<String, dynamic>? incidenciaAtiva = incidenciasList.cast<Map<String, dynamic>?>().firstWhere(
          (i) => i?['line_clearance_validado'] == false,
          orElse: () => null,
        );

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
                              color: emHold ? Colors.red.shade50 : (concluida ? Colors.green.shade50 : Colors.blue.shade50),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: emHold ? Colors.red.shade300 : (concluida ? Colors.green.shade300 : Colors.blue.shade300),
                              ),
                            ),
                            child: Text(
                              emHold ? 'ON HOLD' : (concluida ? 'CONCLUÍDA' : 'EM PRODUÇÃO'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: emHold ? Colors.red.shade800 : (concluida ? Colors.green.shade800 : Colors.blue.shade800),
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
                        if (emHold) ...[
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
                          onPressed: () => _confirmarCancelamento(enc['id'], idFormatado),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.black87),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.black87, fontSize: 12)),
                        ),
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
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancelar Ordem de Produção'),
          content: Text('Tem a certeza de que deseja cancelar e apagar a ordem $refOrdem do sistema?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Não')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _cancelarOrdem(id);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Sim, Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _abrirDialogEditar(Map<String, dynamic> enc) {
    final dataController = TextEditingController(text: enc['data_entrega']);
    final int prodId = enc['tipos_produtos_id'] as int;
    final fasesDisponiveis = List<dynamic>.from(_fasesPorProduto[prodId] ?? []);

    int? faseIdSelecionada = enc['fase_atual_id'] as int?;

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
                        final int id = f['id'] as int;
                        final int ordem = f['ordem'] as int;
                        final String nome = f['nome_fase_padrao'] ?? '';
                        return DropdownMenuItem<int?>(
                          value: id,
                          child: Text('Fase $ordem: $nome'),
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
                      enc['id'],
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