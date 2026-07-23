import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detalhe_tarefa_screen.dart';

class FilaTrabalhoScreen extends StatefulWidget {
  const FilaTrabalhoScreen({super.key});

  @override
  State<FilaTrabalhoScreen> createState() => _FilaTrabalhoScreenState();
}

class _FilaTrabalhoScreenState extends State<FilaTrabalhoScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _encomendasProcessadas = [];
  bool _isLoading = true;
  String? _nomePostoAtivo;

  @override
  void initState() {
    super.initState();
    _carregarFilaDeTrabalho();
  }

  Future<void> _carregarFilaDeTrabalho() async {
    try {
      final utilizadorId = _supabase.auth.currentUser?.id;

      if (utilizadorId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. Busca o posto de trabalho atribuído ao operador logado (Coluna correta: operador_id)
      final postoData = await _supabase
          .from('postos_trabalho')
          .select('id, nome_posto')
          .eq('operador_id', utilizadorId)
          .maybeSingle();

      if (postoData == null) {
        if (mounted) {
          setState(() {
            _nomePostoAtivo = 'Sem Posto Atribuído';
            _encomendasProcessadas = [];
            _isLoading = false;
          });
        }
        return;
      }

      final String nomePosto = postoData['nome_posto'] ?? 'Posto Desconhecido';

      // 2. Busca os IDs das fases_padrao filtrando pelo NOME do posto (Coluna correta: posto_trabalho)
      final fasesDoPostoData = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id')
          .eq('posto_trabalho', nomePosto);

      final List<dynamic> fasesPostoList = fasesDoPostoData as List;
      final List<int> faseIdsDoPosto = fasesPostoList
          .map((f) => f['id'] is int ? f['id'] as int : int.parse(f['id'].toString()))
          .toList();

      // Se este posto não tiver fases associadas, não há tarefas
      if (faseIdsDoPosto.isEmpty) {
        if (mounted) {
          setState(() {
            _nomePostoAtivo = nomePosto;
            _encomendasProcessadas = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 3. Busca APENAS as encomendas cuja fase_atual_id pertence a este posto de trabalho
      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            tipos_produto ( nome_tipo_produto ),
            clientes ( nome_cliente )
          ''')
          .inFilter('fase_atual_id', faseIdsDoPosto);

      // 4. Busca todas as fases padrão dos produtos para calcular o progresso global
      final todasFasesData = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id')
          .order('ordem', ascending: true);

      List<Map<String, dynamic>> listaFinal = [];

      for (var enc in encomendasData) {
        final int tipoProdutoId = enc['tipos_produtos_id'];
        final int? faseAtualId = enc['fase_atual_id'];

        // Filtrar todas as fases associadas a este produto específico
        final fasesDoProduto = (todasFasesData as List)
            .where((f) => f['tipos_produto_id'] == tipoProdutoId)
            .toList();

        final totalFases = fasesDoProduto.length;
        int ordemAtual = 0;

        if (faseAtualId != null) {
          final indexFase = fasesDoProduto.indexWhere((f) => f['id'] == faseAtualId);
          if (indexFase != -1) {
            ordemAtual = fasesDoProduto[indexFase]['ordem'];
          }
        }

        // Progresso = Fases anteriores concluídas / Total de Fases
        double progresso = 0.0;
        if (totalFases > 0 && ordemAtual > 0) {
          progresso = (ordemAtual - 1) / totalFases;
        }

        // Determinação do Estado Visual
        String estado = 'Pronto a Iniciar';
        Color corEstado = const Color(0xFF2563EB); // Azul

        final dataEntrega = DateTime.tryParse(enc['data_entrega'] ?? '');
        final hoje = DateTime.now();

        if (dataEntrega != null && dataEntrega.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) {
          estado = 'Atrasado';
          corEstado = const Color(0xFFDC2626); // Vermelho
        } else if (progresso > 0) {
          estado = 'Em Progresso';
          corEstado = const Color(0xFFD97706); // Laranja
        }

        listaFinal.add({
          'id': enc['id'],
          'codigo_rastreio': enc['codigo_rastreio'],
          'data_entrega': enc['data_entrega'],
          'produto': enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto',
          'cliente': enc['clientes']?['nome_cliente'] ?? 'Sem Cliente',
          'progresso': progresso,
          'estado': estado,
          'corEstado': corEstado,
          'fase_atual_id': faseAtualId,
        });
      }

      if (mounted) {
        setState(() {
          _nomePostoAtivo = nomePosto;
          _encomendasProcessadas = listaFinal;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao construir fila de trabalho: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final largura = MediaQuery.of(context).size.width;
    final colunas = largura > 1200 ? 3 : (largura > 800 ? 2 : 1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho com identificação do Posto de Trabalho
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ordens de Produção',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Cartões atribuídos à sua fila de trabalho',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (_nomePostoAtivo != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.precision_manufacturing_outlined, size: 18, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Text(
                                'Posto: $_nomePostoAtivo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E40AF),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  Expanded(
                    child: _encomendasProcessadas.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  _nomePostoAtivo == 'Sem Posto Atribuído'
                                      ? 'Nenhum posto de trabalho associado ao seu utilizador.'
                                      : 'Não existem ordens de produção pendentes para o seu posto.',
                                  style: const TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: colunas,
                              crossAxisSpacing: 24,
                              mainAxisSpacing: 24,
                              mainAxisExtent: 250,
                            ),
                            itemCount: _encomendasProcessadas.length,
                            itemBuilder: (context, index) {
                              final enc = _encomendasProcessadas[index];
                              final percentagem = (enc['progresso'] * 100).toInt();

                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: Colors.grey.shade200),
                                ),
                                color: Colors.white,
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // ID da Ordem e Tipo de Produto
                                      Text(
                                        enc['codigo_rastreio'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tipo de Produto',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                      ),
                                      Text(
                                        enc['produto'],
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Chip de Estado customizado
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: (enc['corEstado'] as Color).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          enc['estado'],
                                          style: TextStyle(
                                            color: enc['corEstado'],
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),

                                      // Indicador de Progresso e Percentagem
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Progresso Global',
                                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                          ),
                                          Text(
                                            '$percentagem%',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: enc['progresso'],
                                          backgroundColor: const Color(0xFFE2E8F0),
                                          color: const Color(0xFF0F172A),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Botão "Iniciar"
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          final result = await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => DetalheTarefaScreen(
                                                encomendaId: enc['id'],
                                                codigoRastreio: enc['codigo_rastreio'],
                                              ),
                                            ),
                                          );

                                          // Recarrega a fila quando o operador conclui a fase ou reporta incidência
                                          if (result == true) {
                                            setState(() => _isLoading = true);
                                            _carregarFilaDeTrabalho();
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF111827),
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size.fromHeight(40),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(Icons.play_arrow, size: 16),
                                        label: const Text(
                                          'Iniciar',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
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
}