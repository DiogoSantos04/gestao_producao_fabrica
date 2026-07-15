import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/temas_cores.dart';

class GestaoFluxosScreen extends StatefulWidget {
  const GestaoFluxosScreen({super.key});

  @override
  State<GestaoFluxosScreen> createState() => _GestaoFluxosScreenState();
}

class _GestaoFluxosScreenState extends State<GestaoFluxosScreen> {
  final _supabase = Supabase.instance.client;
  
  List<dynamic> _tipologias = [];
  List<dynamic> _fases = [];
  
  Map<String, dynamic>? _tipoProdutoSelecionado;
  bool _isLoadingTipologias = true;
  bool _isLoadingFases = false;

  @override
  void initState() {
    super.initState();
    _carregarTipologias();
  }

  // --- FUNÇÕES DA BASE DE DADOS (SUPABASE - MAPEADAS PARA O TEU ESQUEMA) ---

  Future<void> _carregarTipologias() async {
    try {
      setState(() => _isLoadingTipologias = true);
      // ✅ MAPEADO: Tabela 'tipos_produto' ordenada por 'nome_tipo_produto'
      final data = await _supabase.from('tipos_produto').select().order('nome_tipo_produto');
      
      setState(() {
        _tipologias = data;
        _isLoadingTipologias = false;
        
        if (_tipologias.isNotEmpty && _tipoProdutoSelecionado == null) {
          _selecionarTipologia(_tipologias.first);
        }
      });
    } catch (e) {
      _mostrarErro('Erro ao carregar tipologias: $e');
    }
  }

  Future<void> _carregarFases(int tipoProdutoId) async {
    try {
      setState(() => _isLoadingFases = true);
      // ✅ MAPEADO: Tabela 'fases_padrao' filtrada por 'tipos_produto_id' e ordenada por 'ordem'
      final data = await _supabase
          .from('fases_padrao')
          .select()
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem');

      setState(() {
        _fases = data;
        _isLoadingFases = false;
      });
    } catch (e) {
      _mostrarErro('Erro ao carregar fases: $e');
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
      // ✅ MAPEADO: Insere na coluna 'nome_tipo_produto' da tabela 'tipos_produto'
      await _supabase.from('tipos_produto').insert({'nome_tipo_produto': nome});
      _carregarTipologias();
    } catch (e) {
      _mostrarErro('Erro ao criar tipologia: $e');
    }
  }

  Future<void> _eliminarTipologia(int id) async {
    try {
      await _supabase.from('tipos_produto').delete().eq('id', id);
      setState(() {
        _tipoProdutoSelecionado = null;
        _fases = [];
      });
      _carregarTipologias();
    } catch (e) {
      _mostrarErro('Erro ao eliminar tipologia: $e');
    }
  }

  Future<void> _salvarFase({
    int? id,
    required String nome,
    required String descricao,
    required String posto,
    required int tempo,
    required List<String> checklist,
  }) async {
    try {
      if (_tipoProdutoSelecionado == null) return;

      // ✅ MAPEADO: Chaves correspondentes às tuas colunas e às novas colunas do OEE
      final dadosFase = {
        'tipos_produto_id': _tipoProdutoSelecionado!['id'],
        'nome_fase_padrao': nome,
        'descricao': descricao,
        'posto_trabalho': posto,
        'tempo_estimado': tempo,
        'checklist': checklist,
        'ordem': id == null ? (_fases.length + 1) : null,
      };

      dadosFase.removeWhere((key, value) => value == null);

      if (id == null) {
        await _supabase.from('fases_padrao').insert(dadosFase);
      } else {
        await _supabase.from('fases_padrao').update(dadosFase).eq('id', id);
      }

      _carregarFases(_tipoProdutoSelecionado!['id']);
    } catch (e) {
      _mostrarErro('Erro ao guardar fase: $e');
    }
  }

  Future<void> _eliminarFase(int id) async {
    try {
      await _supabase.from('fases_padrao').delete().eq('id', id);
      _carregarFases(_tipoProdutoSelecionado!['id']);
    } catch (e) {
      _mostrarErro('Erro ao eliminar fase: $e');
    }
  }

  Future<void> _reordenarFases(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    
    setState(() {
      final item = _fases.removeAt(oldIndex);
      _fases.insert(newIndex, item);
    });

    try {
      // ✅ MAPEADO: Atualiza a ordenação das fases_padrao
      for (int i = 0; i < _fases.length; i++) {
        await _supabase
            .from('fases_padrao')
            .update({'ordem': i + 1})
            .eq('id', _fases[i]['id']);
      }
    } catch (e) {
      _mostrarErro('Erro ao guardar nova ordenação: $e');
    }
  }

  void _mostrarErro(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: TemasCores.vermelhoErro),
      );
    }
  }

  // --- INTERFACE GRÁFICA (UI) ---

  @override
  Widget build(BuildContext context) {
    final double larguraEcra = MediaQuery.of(context).size.width;
    final bool eDesktop = larguraEcra > 850;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
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
                        Expanded(flex: 1, child: _buildPainelEsquerdoTipologias()),
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

  Widget _buildPainelEsquerdoTipologias() {
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
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
            Text(
              'Selecione uma tipologia para desenhar o fluxo',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 16),
            _isLoadingTipologias
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _tipologias.length,
                    itemBuilder: (context, index) {
                      final tipo = _tipologias[index];
                      final bool eSelecionado =
                          _tipoProdutoSelecionado?['id'] == tipo['id'];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: eSelecionado ? Colors.blue : Colors.grey.shade200,
                            width: eSelecionado ? 2 : 1,
                          ),
                          color: eSelecionado ? Colors.blue.withOpacity(0.05) : Colors.transparent,
                        ),
                        child: ListTile(
                          // ✅ MAPEADO: nome_tipo_produto
                          title: Text(
                            tipo['nome_tipo_produto'] ?? '',
                            style: TextStyle(
                              fontWeight: eSelecionado ? FontWeight.bold : FontWeight.normal,
                              color: eSelecionado ? Colors.blue.shade800 : Colors.black87,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                              if (eSelecionado)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  onPressed: () => _eliminarTipologia(tipo['id']),
                                ),
                            ],
                          ),
                          onTap: () => _selecionarTipologia(tipo),
                        ),
                      );
                    },
                  ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _abrirDialogNovaTipologia,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(45),
                backgroundColor: Colors.grey.shade100,
                foregroundColor: Colors.black87,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Nova Tipologia'),
            ),
          ],
        ),
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
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ✅ MAPEADO: nome_tipo_produto
                    Text(
                      'Fluxo Produtivo: ${_tipoProdutoSelecionado!['nome_tipo_produto']}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Defina o circuito sequencial de produção das peças',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _abrirDialogFase(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar Fase'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_fases.isNotEmpty) _buildBreadcrumbsFases(),

            const SizedBox(height: 24),

            _isLoadingFases
                ? const Center(child: CircularProgressIndicator())
                : _fases.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'Nenhuma fase definida para este fluxo.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : SizedBox(
                        height: 400,
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: true,
                          itemCount: _fases.length,
                          onReorder: _reordenarFases,
                          itemBuilder: (context, index) {
                            final fase = _fases[index];
                            final checklistItems = List<String>.from(fase['checklist'] ?? []);

                            return Card(
                              key: ValueKey(fase['id']),
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.drag_indicator, color: Colors.grey),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Fase ${index + 1}',
                                                  style: TextStyle(
                                                    color: Colors.blue.shade700,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // ✅ MAPEADO: nome_fase_padrao
                                              Text(
                                                fase['nome_fase_padrao'] ?? '',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              ),
                                              const Spacer(),
                                              if (fase['posto_trabalho'] != null && fase['posto_trabalho'].toString().isNotEmpty)
                                                Chip(
                                                  avatar: const Icon(Icons.precision_manufacturing, size: 12),
                                                  label: Text(
                                                    fase['posto_trabalho'],
                                                    style: const TextStyle(fontSize: 10),
                                                  ),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              const SizedBox(width: 6),
                                              Chip(
                                                avatar: const Icon(Icons.timer_outlined, size: 12),
                                                label: Text(
                                                  '${fase['tempo_estimado']} min',
                                                  style: const TextStyle(fontSize: 10),
                                                ),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            fase['descricao'] ?? 'Sem descrição.',
                                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                          ),
                                          if (checklistItems.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: checklistItems.map((item) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.green.shade200),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.check_box_outlined, size: 11, color: Colors.green.shade700),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        item,
                                                        style: TextStyle(fontSize: 10, color: Colors.green.shade800),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            )
                                          ]
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, color: Colors.grey, size: 20),
                                      onPressed: () => _abrirDialogFase(faseExistente: fase),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () => _eliminarFase(fase['id']),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF111625),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  // ✅ MAPEADO: nome_fase_padrao
                  'Fase ${index + 1}: ${f['nome_fase_padrao']}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (!eUltimo)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.chevron_right, color: Colors.grey, size: 16),
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
            decoration: const InputDecoration(labelText: 'Nome da Tipologia (Ex: Cadeiras, Sofás)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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

  void _abrirDialogFase({Map<String, dynamic>? faseExistente}) {
    // ✅ MAPEADO: nome_fase_padrao
    final nomeController = TextEditingController(text: faseExistente?['nome_fase_padrao'] ?? '');
    final descController = TextEditingController(text: faseExistente?['descricao'] ?? '');
    final postoController = TextEditingController(text: faseExistente?['posto_trabalho'] ?? '');
    final tempoController = TextEditingController(text: faseExistente?['tempo_estimado']?.toString() ?? '15');
    
    List<String> checklistLocal = List<String>.from(faseExistente?['checklist'] ?? []);
    final taskController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(faseExistente == null ? 'Adicionar Fase de Produção' : 'Editar Fase de Produção'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nomeController,
                        decoration: const InputDecoration(labelText: 'Nome da Fase * (Ex: Corte, Costura)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descController,
                        decoration: const InputDecoration(labelText: 'Descrição sumária da atividade'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: postoController,
                              decoration: const InputDecoration(labelText: 'Posto de Trabalho (Ex: CNC-01)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: tempoController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Tempo Estimado (min)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '📋 Checklist SOP (Passos obrigatórios do Operador):',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: taskController,
                              decoration: const InputDecoration(
                                labelText: 'Adicionar passo (Ex: Confirmar dimensões)',
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.blue),
                            onPressed: () {
                              if (taskController.text.isNotEmpty) {
                                setDialogState(() {
                                  checklistLocal.add(taskController.text.trim());
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
                              title: Text(checklistLocal[idx], style: const TextStyle(fontSize: 12)),
                              dense: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 16),
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
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    if (nomeController.text.isNotEmpty) {
                      _salvarFase(
                        id: faseExistente?['id'],
                        nome: nomeController.text.trim(),
                        descricao: descController.text.trim(),
                        posto: postoController.text.trim(),
                        tempo: int.tryParse(tempoController.text) ?? 15,
                        checklist: checklistLocal,
                      );
                      Navigator.pop(context);
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