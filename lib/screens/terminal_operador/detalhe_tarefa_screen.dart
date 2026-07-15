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
  
  Map<String, dynamic>? _encomenda;
  List<dynamic> _fasesDoProduto = [];
  int? _faseAtualId;
  bool _isBloqueada = false;

  @override
  void initState() {
    super.initState();
    _carregarDetalhesTarefa();
  }

  Future<void> _carregarDetalhesTarefa() async {
    try {
      // 1. Carrega dados da encomenda e tipo de produto
      final encomendaData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            tipos_produtos_id,
            fase_atual_id,
            tipos_produto ( nome_tipo_produto )
          ''')
          .eq('id', widget.encomendaId)
          .single();

      _faseAtualId = encomendaData['fase_atual_id'];

      // 2. Carrega todas as fases padrão deste tipo de produto ordenadas
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('id, nome_fase_padrao, ordem')
          .eq('tipos_produto_id', encomendaData['tipos_produtos_id'])
          .order('ordem', ascending: true);

      // 3. Verifica se a encomenda tem alguma incidência em aberto
      final incidenciasData = await _supabase
          .from('incidencias')
          .select('id, historico_producao!inner(encomenda_id)')
          .eq('historico_producao.encomenda_id', widget.encomendaId);

      // Se existir algum registo na tabela incidências associado a este ID de encomenda, consideramos bloqueada
      _isBloqueada = (incidenciasData as List).isNotEmpty;

      setState(() {
        _encomenda = encomendaData;
        _fasesDoProduto = fasesData;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar detalhes da tarefa: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Transição automática para a próxima fase na Máquina de Estados
  Future<void> _concluirFase() async {
    if (_encomenda == null || _faseAtualId == null) return;

    setState(() => _isLoading = true);

    try {
      final int tipoProdutoId = _encomenda!['tipos_produtos_id'];
      
      // Encontra o índice e a ordem da fase atual
      final indexFaseAtual = _fasesDoProduto.indexWhere((f) => f['id'] == _faseAtualId);
      final int ordemAtual = _fasesDoProduto[indexFaseAtual]['ordem'];

      // Procura se existe uma próxima fase (ordem atual + 1)
      final proximaFaseData = await _supabase
          .from('fases_padrao')
          .select('id, nome_fase_padrao')
          .eq('tipos_produto_id', tipoProdutoId)
          .eq('ordem', ordemAtual + 1)
          .maybeSingle();

      final utilizadorId = _supabase.auth.currentUser?.id;

      // 1. Insere o log de encerramento de fase no Histórico de Produção
      await _supabase.from('historico_producao').insert({
        'encomenda_id': widget.encomendaId,
        'fase_concluida_id': _faseAtualId,
        'utilizador_id': utilizadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      // 2. Atualiza o estado da encomenda no Supabase
      if (proximaFaseData != null) {
        // Passa para a fase seguinte
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': proximaFaseData['id']})
            .eq('id', widget.encomendaId);
      } else {
        // Concluiu a última fase padrão (Encomenda totalmente finalizada)
        await _supabase
            .from('encomendas')
            .update({'fase_atual_id': null})
            .eq('id', widget.encomendaId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Operação registada com sucesso!'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop(true); // Retorna true para refrescar a fila
      }
    } catch (e) {
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
    }
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
                    // Cabeçalho da Ordem
                    Text(
                      widget.codigoRastreio,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Execução de Tarefa',
                      style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 32),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Coluna da Esquerda: Especificações Técnicas (Tabela Mockup - Figura 31)
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
                                      _construirLinhaEspecificacao('Cor:', 'Natural Metálico'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // Botões de Ação Inferiores
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: ElevatedButton(
                                      onPressed: _isBloqueada || _faseAtualId == null ? null : _concluirFase,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981), // Verde
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        elevation: 0,
                                      ),
                                      child: const Text('Concluir Fase', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _isBloqueada ? null : _abrirPopupIncidencia,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFEF4444), // Vermelho
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

                        // Coluna da Direita: Timeline de Fases de Produção (Figura 31)
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

  Widget _construirLinhaEspecificacao(String label, String valor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500, fontSize: 13)),
        Text(valor, style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  // Desenha a árvore vertical de fases (Timeline)
  Widget _construirTimelineFases() {
    // Determinar índice da fase atual
    final indexFaseAtual = _fasesDoProduto.indexWhere((f) => f['id'] == _faseAtualId);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _fasesDoProduto.length,
      itemBuilder: (context, index) {
        final fase = _fasesDoProduto[index];
        final String nome = fase['nome_fase_padrao'];
        
        bool isConcluida = false;
        bool isAtual = false;

        if (_faseAtualId == null) {
          isConcluida = true; // Se não há fase atual, a encomenda já terminou tudo
        } else if (index < indexFaseAtual) {
          isConcluida = true;
        } else if (index == indexFaseAtual) {
          isAtual = true;
        }

        return IntrinsicHeight(
          child: Row(
            children: [
              // Linha e Círculo da Timeline
              Column(
                children: [
                  // Círculo
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isConcluida 
                          ? const Color(0xFF10B981) // Verde para as concluídas
                          : (isAtual ? const Color(0xFF3B82F6) : Colors.grey.shade100), // Azul ou cinzento
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
                  // Linha conetora (não desenhar para o último elemento)
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
              
              // Texto descritivo da Fase
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
                    const SizedBox(height: 20), // Espaçamento entre nós
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