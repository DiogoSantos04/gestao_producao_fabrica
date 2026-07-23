import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'popups/bloquear_tarefa_screen.dart';

class DetalheTarefaScreen extends StatefulWidget {
  final int encomendaId;
  final String codigoRastreio;

  const DetalheTarefaScreen({
    super.key,
    required this.encomendaId,
    required this.codigoRastreio,
  });

  @override
  State<DetalheTarefaScreen> createState() => _DetalheTarefaScreenState();
}

class _DetalheTarefaScreenState extends State<DetalheTarefaScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _encomenda;
  List<dynamic> _fasesDoProduto = [];
  int? _faseAtualId;
  bool _isBloqueada = false;

  // --- REGISTO ESTÁTICO EM MEMÓRIA (PERSISTE ENTRE PÁGINAS E NAVEGAÇÃO) ---
  static final Map<String, DateTime> _temposInicioFase = {};

  // --- MÓDULO ANDON & CRONÓMETRO ---
  Timer? _timerAndon;
  int _segundosDecorridos = 0;
  int _tempoEstimadoMinutos = 15;

  @override
  void initState() {
    super.initState();
    _carregarDetalhesTarefa();
  }

  @override
  void dispose() {
    _timerAndon?.cancel();
    super.dispose();
  }

  void _iniciarCronometroAndon() {
    _timerAndon?.cancel();
    _timerAndon = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _segundosDecorridos++;
        });
      }
    });
  }

  Future<void> _carregarDetalhesTarefa() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Carrega a encomenda pelo ID
      final encomendaRes = await _supabase
          .from('encomendas')
          .select('*')
          .eq('id', widget.encomendaId)
          .single();

      _encomenda = encomendaRes;
      _faseAtualId = _encomenda!['fase_atual_id'];
      final bool emSuspenso = _encomenda!['em_suspenso'] == true;

      // Extrai ID do tipo de produto
      dynamic rawTipoId = _encomenda!['tipos_produtos_id'] ?? _encomenda!['tipos_produto_id'] ?? _encomenda!['tipo_produto_id'];
      int? tipoProdutoId = rawTipoId is int ? rawTipoId : int.tryParse(rawTipoId?.toString() ?? '');

      // 2. Busca o Nome Real do Produto
      String nomeProduto = 'Artigo';
      if (tipoProdutoId != null) {
        try {
          final tpRes = await _supabase
              .from('tipos_produto')
              .select('nome_tipo_produto')
              .eq('id', tipoProdutoId)
              .maybeSingle();

          if (tpRes != null && tpRes['nome_tipo_produto'] != null) {
            nomeProduto = tpRes['nome_tipo_produto'].toString();
          }
        } catch (e) {
          debugPrint('Aviso ao carregar tipo_produto: $e');
        }
      }
      _encomenda!['nome_tipo_produto'] = nomeProduto;

      // 3. Busca as Fases de Produção do Produto
      List<dynamic> fases = [];
      if (tipoProdutoId != null) {
        try {
          fases = await _supabase
              .from('fases_padrao')
              .select('*')
              .eq('tipos_produto_id', tipoProdutoId)
              .order('ordem', ascending: true);
        } catch (e) {
          debugPrint('Aviso na busca de fases por tipos_produto_id: $e');
        }

        if (fases.isEmpty) {
          try {
            fases = await _supabase
                .from('fases_padrao')
                .select('*')
                .eq('tipos_produtos_id', tipoProdutoId)
                .order('ordem', ascending: true);
          } catch (e) {
            debugPrint('Aviso no fallback de fases: $e');
          }
        }
      }

      // Fallback: Se a encomenda tem fase_atual_id, descobre a sequência
      if (fases.isEmpty && _faseAtualId != null) {
        try {
          final faseAtualBD = await _supabase
              .from('fases_padrao')
              .select('*')
              .eq('id', _faseAtualId!)
              .maybeSingle();

          if (faseAtualBD != null) {
            final dynamic realTipoIdRaw = faseAtualBD['tipos_produto_id'] ?? faseAtualBD['tipos_produtos_id'];
            final int? realTipoId = realTipoIdRaw is int ? realTipoIdRaw : int.tryParse(realTipoIdRaw?.toString() ?? '');

            if (realTipoId != null) {
              fases = await _supabase
                  .from('fases_padrao')
                  .select('*')
                  .eq('tipos_produto_id', realTipoId)
                  .order('ordem', ascending: true);
            }
          }
        } catch (e) {
          debugPrint('Aviso na busca por fase_atual_id: $e');
        }
      }

      _fasesDoProduto = fases;

      // Se a fase atual não estiver na lista, ajusta para a primeira
      if (_fasesDoProduto.isNotEmpty) {
        final existeFase = _fasesDoProduto.any((f) => f['id'] == _faseAtualId);
        if (!existeFase) {
          _faseAtualId = _fasesDoProduto.first['id'];
        }
      }

      // 4. Ajusta o Tempo Estimado da Fase Atual
      if (_faseAtualId != null && _fasesDoProduto.isNotEmpty) {
        final fasesCorrespondentes = _fasesDoProduto.where((f) => f['id'] == _faseAtualId);
        final dynamic faseAtual = fasesCorrespondentes.isNotEmpty ? fasesCorrespondentes.first : _fasesDoProduto.first;

        if (faseAtual != null && faseAtual['tempo_estimado'] != null) {
          _tempoEstimadoMinutos = faseAtual['tempo_estimado'] is int
              ? faseAtual['tempo_estimado']
              : int.tryParse(faseAtual['tempo_estimado'].toString()) ?? 15;
        }
      }

      // =======================================================================
      // 5. CÁLCULO CONTINUO DO TEMPO (IMUNE A NAVEGAÇÕES ENTRE PÁGINAS)
      // =======================================================================
      if (_faseAtualId != null) {
        final String chaveFase = '${widget.encomendaId}_$_faseAtualId';

        if (_temposInicioFase.containsKey(chaveFase)) {
          // Já foi iniciada anteriormente durante a sessão
          final inicio = _temposInicioFase[chaveFase]!;
          _segundosDecorridos = DateTime.now().difference(inicio).inSeconds;
          if (_segundosDecorridos < 0) _segundosDecorridos = 0;
        } else {
          // Primeira vez que entra nesta fase nesta sessão
          DateTime? inicioBD;
          try {
            final historicoAnterior = await _supabase
                .from('historico_producao')
                .select('data_conclusao')
                .eq('encomenda_id', widget.encomendaId)
                .order('data_conclusao', ascending: false)
                .limit(1)
                .maybeSingle();

            if (historicoAnterior != null && historicoAnterior['data_conclusao'] != null) {
              inicioBD = DateTime.tryParse(historicoAnterior['data_conclusao'].toString())?.toLocal();
            }
          } catch (e) {
            debugPrint('Aviso ao ler histórico: $e');
          }

          final agora = DateTime.now();
          if (inicioBD != null && agora.difference(inicioBD).inSeconds >= 0 && agora.difference(inicioBD).inHours < 12) {
            _temposInicioFase[chaveFase] = inicioBD;
            _segundosDecorridos = agora.difference(inicioBD).inSeconds;
          } else {
            _temposInicioFase[chaveFase] = agora;
            _segundosDecorridos = 0;
          }
        }
      }

      // 6. Verifica se há incidências pendentes
      bool temIncidenciaAtiva = false;
      try {
        final incidenciasData = await _supabase
            .from('incidencias')
            .select('id, line_clearance_validado')
            .eq('encomenda_id', widget.encomendaId);

        if (incidenciasData is List) {
          temIncidenciaAtiva = incidenciasData.any((inc) => inc['line_clearance_validado'] != true);
        }
      } catch (e) {
        debugPrint('Aviso em incidências: $e');
      }

      _isBloqueada = emSuspenso || temIncidenciaAtiva;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      if (!_isBloqueada && _faseAtualId != null) {
        _iniciarCronometroAndon();
      }
    } catch (e, stack) {
      debugPrint('Erro ao carregar detalhes: $e\n$stack');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Poka-Yoke: Checklist Obrigatória antes de concluir a fase
  Future<bool> _validarChecklistQualidade(List<dynamic> checklistRaw) async {
    if (checklistRaw.isEmpty) return true;

    final List<String> itens = checklistRaw.map((e) {
      if (e is Map) return e['item']?.toString() ?? e.toString();
      return e.toString();
    }).toList();

    Map<int, bool> verificados = {for (int i = 0; i < itens.length; i++) i: false};

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool todosVerificados = verificados.values.every((v) => v == true);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.fact_check_outlined, color: Color(0xFF2563EB), size: 28),
                  SizedBox(width: 10),
                  Text('Checklist de Qualidade', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Confirme a validação de todos os pontos de controlo antes de encerrar a etapa:',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(itens.length, (index) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: verificados[index] == true ? const Color(0xFFF0FDF4) : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: verificados[index] == true ? const Color(0xFFBBF7D0) : Colors.grey.shade200,
                              ),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                itens[index],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: verificados[index] == true ? const Color(0xFF15803D) : const Color(0xFF1E293B),
                                ),
                              ),
                              value: verificados[index],
                              activeColor: const Color(0xFF10B981),
                              onChanged: (val) {
                                setModalState(() {
                                  verificados[index] = val ?? false;
                                });
                              },
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: todosVerificados ? () => Navigator.pop(context, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Validar & Concluir Fase'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Future<void> _solicitarConclusaoFase() async {
    if (_encomenda == null || _faseAtualId == null) return;

    final fasesCorrespondentes = _fasesDoProduto.where((f) => f['id'] == _faseAtualId);
    final dynamic faseAtual = fasesCorrespondentes.isNotEmpty ? fasesCorrespondentes.first : null;

    if (faseAtual != null && faseAtual['checklist'] != null) {
      final dynamic rawChecklist = faseAtual['checklist'];
      List<dynamic> checklist = [];

      if (rawChecklist is List) {
        checklist = rawChecklist;
      } else if (rawChecklist is String) {
        try {
          checklist = jsonDecode(rawChecklist);
        } catch (_) {}
      }

      if (checklist.isNotEmpty) {
        final bool validado = await _validarChecklistQualidade(checklist);
        if (!validado) return;
      }
    }

    _concluirFase();
  }

  // Transição de Fase no Supabase
  Future<void> _concluirFase() async {
    if (_faseAtualId == null || _encomenda == null) return;

    setState(() => _isLoading = true);
    _timerAndon?.cancel();

    try {
      final indexFaseAtual = _fasesDoProduto.indexWhere((f) => f['id'] == _faseAtualId);

      int? proximaFaseId;
      if (indexFaseAtual != -1 && indexFaseAtual + 1 < _fasesDoProduto.length) {
        proximaFaseId = _fasesDoProduto[indexFaseAtual + 1]['id'];
      }

      final utilizadorId = _supabase.auth.currentUser?.id;

      // Limpa a fase antiga da memória
      _temposInicioFase.remove('${widget.encomendaId}_$_faseAtualId');

      // 1. Regista no Histórico de Produção
      await _supabase.from('historico_producao').insert({
        'encomenda_id': widget.encomendaId,
        'fase_concluida_id': _faseAtualId,
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      // 2. Atualiza a encomenda com o ID da próxima fase
      await _supabase
          .from('encomendas')
          .update({'fase_atual_id': proximaFaseId})
          .eq('id', widget.encomendaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Etapa concluída com sucesso! Encomenda avançada. 🚀'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('Erro ao concluir fase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar fase: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _abrirPopupIncidencia() async {
    if (_faseAtualId == null) return;

    _timerAndon?.cancel();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BloquearTarefaPopup(
        encomendaId: widget.encomendaId,
        codigoRastreio: widget.codigoRastreio,
        faseAtualId: _faseAtualId!,
      ),
    );

    if (result == true) {
      setState(() => _isLoading = true);
      _carregarDetalhesTarefa();
    } else {
      _iniciarCronometroAndon();
    }
  }

  String _formatarTempo(int totalSegundos) {
    final duracao = Duration(seconds: totalSegundos);
    final horas = duracao.inHours.toString().padLeft(2, '0');
    final minutos = (duracao.inMinutes % 60).toString().padLeft(2, '0');
    final segundos = (duracao.inSeconds % 60).toString().padLeft(2, '0');
    return '$horas:$minutos:$segundos';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.codigoRastreio, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(40.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Text('Erro ao carregar dados: $_errorMessage', style: TextStyle(color: Colors.red.shade900)),
                      ),

                    Text(
                      widget.codigoRastreio,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Produto: ${_encomenda?['nome_tipo_produto'] ?? 'Artigo'}',
                      style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),

                    // --- BLOCO ANDON VISUAL ---
                    if (!_isBloqueada && _faseAtualId != null) _construirCardAndon(),

                    const SizedBox(height: 24),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Coluna Esquerda: Especificações + Botões
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Especificações Técnicas',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                      ),
                                      const SizedBox(height: 16),
                                      _construirLinhaEspecificacao('Dimensões:', '500mm x 300mm x 150mm'),
                                      const Divider(height: 24),
                                      _construirLinhaEspecificacao('Material:', 'Aço Inoxidável 304'),
                                      const Divider(height: 24),
                                      _construirLinhaEspecificacao('Tempo Estimado da Fase:', '$_tempoEstimadoMinutos min'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Botões
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton.icon(
                                      onPressed: _isBloqueada || _faseAtualId == null ? null : _solicitarConclusaoFase,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      icon: const Icon(Icons.check_circle_outline, size: 20),
                                      label: const Text('Concluir Fase', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _isBloqueada ? null : _abrirPopupIncidencia,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFEF4444),
                                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.warning_amber_rounded, size: 18),
                                      label: const Text('Reportar Incidência', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 32),

                        // Coluna Direita: Timeline de Fases
                        Expanded(
                          flex: 2,
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Fases de Produção',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                  ),
                                  const SizedBox(height: 24),
                                  _construirTimelineFases(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _construirCardAndon() {
    final int tempoEstimadoSegundos = _tempoEstimadoMinutos * 60;
    final double racio = tempoEstimadoSegundos > 0 ? (_segundosDecorridos / tempoEstimadoSegundos) : 0;

    Color corAndon = const Color(0xFF10B981);
    String estadoAndon = 'DENTRO DO PRAZO';

    if (racio > 1.0) {
      corAndon = const Color(0xFFEF4444);
      estadoAndon = 'TEMPO ESTIMADO EXCEDIDO';
    } else if (racio >= 0.8) {
      corAndon = const Color(0xFFF59E0B);
      estadoAndon = 'ATENÇÃO AO LIMITE';
    }

    return Card(
      elevation: 0,
      color: corAndon.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: corAndon.withOpacity(0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: corAndon, shape: BoxShape.circle),
              child: const Icon(Icons.timer_outlined, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        estadoAndon,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: corAndon),
                      ),
                      Text(
                        'Estimado: $_tempoEstimadoMinutos min',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatarTempo(_segundosDecorridos),
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: corAndon),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirLinhaEspecificacao(String label, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500, fontSize: 13)),
        Text(valor, style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _construirTimelineFases() {
    if (_fasesDoProduto.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'Nenhuma fase configurada para este produto.',
          style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
        ),
      );
    }

    final indexFaseAtual = _fasesDoProduto.indexWhere((f) => f['id'] == _faseAtualId);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _fasesDoProduto.length,
      itemBuilder: (context, index) {
        final fase = _fasesDoProduto[index];
        final String nome = fase['nome_fase_padrao'] ?? fase['nome_fase'] ?? 'Fase #${index + 1}';

        bool isConcluida = false;
        bool isAtual = false;

        if (_faseAtualId == null) {
          isConcluida = true;
        } else if (indexFaseAtual != -1 && index < indexFaseAtual) {
          isConcluida = true;
        } else if (index == indexFaseAtual || (indexFaseAtual == -1 && index == 0)) {
          isAtual = true;
        }

        return IntrinsicHeight(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isConcluida
                          ? const Color(0xFF10B981)
                          : (isAtual ? const Color(0xFF3B82F6) : Colors.grey.shade100),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isConcluida
                            ? Colors.transparent
                            : (isAtual ? Colors.transparent : Colors.grey.shade300),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: isConcluida
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isAtual ? Colors.white : Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                  if (index != _fasesDoProduto.length - 1)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isConcluida ? const Color(0xFF10B981) : Colors.grey.shade200,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isAtual ? FontWeight.bold : FontWeight.w500,
                        color: isAtual
                            ? const Color(0xFF1E293B)
                            : (isConcluida ? const Color(0xFF64748B) : Colors.grey.shade400),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConcluida
                          ? 'Concluída'
                          : (isAtual ? 'Em andamento...' : 'Aguardando'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isConcluida
                            ? const Color(0xFF10B981)
                            : (isAtual ? const Color(0xFF3B82F6) : Colors.grey.shade400),
                        fontWeight: isAtual ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}