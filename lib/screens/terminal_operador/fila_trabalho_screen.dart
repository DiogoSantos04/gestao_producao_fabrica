import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'detalhe_tarefa_screen.dart'; // Será criado no próximo passo

class FilaTrabalhoScreen extends StatefulWidget {
  const FilaTrabalhoScreen({super.key});

  @override
  State<FilaTrabalhoScreen> createState() => _FilaTrabalhoScreenState();
}

class _FilaTrabalhoScreenState extends State<FilaTrabalhoScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _encomendasProcessadas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarFilaDeTrabalho();
  }

  Future<void> _carregarFilaDeTrabalho() async {
    try {
      // 1. Busca encomendas ativas (fase_atual_id não é nulo)
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
          .not('fase_atual_id', 'is', null);

      // 2. Busca todas as fases padrão para calcularmos o progresso e estados corretos
      final fasesData = await _supabase
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id')
          .order('ordem', ascending: true);

      // 3. Cruzamento de dados na aplicação para obter métricas exatas por cartão
      List<Map<String, dynamic>> listaFinal = [];

      for (var enc in encomendasData) {
        final int tipoProdutoId = enc['tipos_produtos_id'];
        final int? faseAtualId = enc['fase_atual_id'];

        // Filtrar todas as fases associadas a este produto específico
        final fasesDoProduto = fasesData
            .where((f) => f['tipos_produto_id'] == tipoProdutoId)
            .toList();

        final totalFases = fasesDoProduto.length;
        int ordemAtual = 0;
        
        if (faseAtualId != null) {
          final indexFase = fasesDoProduto.indexWhere((f) => f['id'] == faseAtualId);
          if (indexFase != -indexFase) {
            ordemAtual = fasesDoProduto[indexFase]['ordem'];
          }
        }

        // Progresso = Fases anteriores concluídas / Total de Fases
        double progresso = 0.0;
        if (totalFases > 0 && ordemAtual > 0) {
          progresso = (ordemAtual - 1) / totalFases;
        }

        // Determinação do Estado Visual (Figura 30)
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
    // Layout responsivo de 2 ou 3 colunas dependendo do espaço do ecrã
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
                  // Cabeçalho conforme Figura 30
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
                  const SizedBox(height: 32),

                  Expanded(
                    child: _encomendasProcessadas.isEmpty
                        ? const Center(
                            child: Text(
                              'Não existem ordens de produção ativas de momento.',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
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

                                      // Chip de Estado customizado (Pronto a iniciar, progresso, atrasado)
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
                                            'Progresso',
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
                                          color: const Color(0xFF0F172A), // Barra escura profissional
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Botão "Iniciar" estilizado
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
                                          if (result == true) {
                                            setState(() => _isLoading = true);
                                            _carregarFilaDeTrabalho();
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF111827), // Botão Dark Blue do mockup
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