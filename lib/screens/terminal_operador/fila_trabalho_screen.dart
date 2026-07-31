import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/estado_ordem.dart';
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

      // 3. Busca APENAS as encomendas cuja fase_atual_id pertence a este posto
      // de trabalho.
      //
      // O filtro `cancelada = false` é aplicado no servidor: sem ele, uma ordem
      // cancelada continuava a aparecer na fila e o operador podia iniciá-la.
      // As ordens em WIP Hold continuam visíveis — escondê-las deixaria o
      // operador sem saber para onde foi o trabalho —, mas entram marcadas e com
      // o botão desativado. Ver bug (E) em AlteracoesNoOperador.md.
      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            cancelada,
            em_suspenso,
            tipos_produto ( nome_tipo_produto ),
            clientes ( nome_cliente )
          ''')
          .eq('cancelada', false)
          .inFilter('fase_atual_id', faseIdsDoPosto);

      // 4. Busca as fases padrão necessárias para calcular o progresso global.
      //
      // Só se procuram as fases dos tipos de produto que aparecem mesmo na
      // fila: antes carregava-se a tabela `fases_padrao` inteira, sem filtro,
      // para depois a filtrar em memória.
      final Set<int> tiposProdutoNaFila = encomendasData
          .map((e) => e['tipos_produtos_id'])
          .whereType<int>()
          .toSet();

      final List<dynamic> todasFasesData = tiposProdutoNaFila.isEmpty
          ? const []
          : await _supabase
              .from('fases_padrao')
              .select('id, ordem, tipos_produto_id')
              .inFilter('tipos_produto_id', tiposProdutoNaFila.toList())
              .order('ordem', ascending: true);

      List<Map<String, dynamic>> listaFinal = [];

      for (var enc in encomendasData) {
        // Sem verificação de nulo, uma encomenda sem tipo de produto atribuído
        // rebentava aqui com `TypeError` e derrubava a fila inteira.
        final int? tipoProdutoId = enc['tipos_produtos_id'] as int?;
        final int? faseAtualId = enc['fase_atual_id'];

        // Filtrar todas as fases associadas a este produto específico
        final fasesDoProduto = tipoProdutoId == null
            ? const []
            : todasFasesData
                .where((f) => f['tipos_produto_id'] == tipoProdutoId)
                .toList();

        final totalFases = fasesDoProduto.length;

        // Progresso = fases já concluídas / total de fases.
        //
        // Usa-se a posição da fase na lista ordenada, não o valor da coluna
        // `ordem`: o cálculo anterior — `(ordem - 1) / total` — assumia que
        // `ordem` era contígua e começava em 1. Numerações com saltos (uma fase
        // removida do plano) davam percentagens erradas, incluindo acima de
        // 100%.
        double progresso = 0.0;
        if (totalFases > 0 && faseAtualId != null) {
          final indexFase =
              fasesDoProduto.indexWhere((f) => f['id'] == faseAtualId);
          if (indexFase != -1) {
            progresso = indexFase / totalFases;
          }
        }

        // Determinação do Estado Visual.
        //
        // O estado de negócio é derivado por `EstadoOrdem`, a definição única
        // partilhada com o admin — antes este ecrã tinha regras próprias e
        // etiquetas que não coincidiam com nenhuma das do painel de controlo.
        // "Atrasado" e "Em Progresso" continuam a existir como leitura
        // operacional, mas só se aplicam a uma ordem que esteja mesmo em
        // produção.
        final EstadoOrdem estadoOrdem = EstadoOrdem.derivar(
          cancelada: enc['cancelada'] == true,
          emSuspenso: enc['em_suspenso'] == true,
          temFaseAtual: faseAtualId != null,
        );

        String estado = 'Pronto a Iniciar';
        Color corEstado = const Color(0xFF2563EB); // Azul

        if (estadoOrdem == EstadoOrdem.emHold) {
          estado = estadoOrdem.etiqueta; // 'ON HOLD'
          corEstado = const Color(0xFF9333EA); // Roxo — bloqueio, não atraso
        } else {
          final dataEntrega = DateTime.tryParse(enc['data_entrega'] ?? '');
          final hoje = DateTime.now();

          if (dataEntrega != null &&
              dataEntrega.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) {
            estado = 'Atrasado';
            corEstado = const Color(0xFFDC2626); // Vermelho
          } else if (progresso > 0) {
            estado = 'Em Progresso';
            corEstado = const Color(0xFFD97706); // Laranja
          }
        }

        listaFinal.add({
          'id': enc['id'],
          'codigo_rastreio': enc['codigo_rastreio'] ?? 'Sem Referência',
          'data_entrega': enc['data_entrega'],
          'produto': enc['tipos_produto']?['nome_tipo_produto'] ?? 'Sem Produto',
          'cliente': enc['clientes']?['nome_cliente'] ?? 'Sem Cliente',
          'progresso': progresso,
          'estado': estado,
          'corEstado': corEstado,
          'fase_atual_id': faseAtualId,
          // Uma ordem em hold não é trabalhável: o botão fica desativado até o
          // Line Clearance ser aprovado no painel do admin.
          'bloqueada': estadoOrdem == EstadoOrdem.emHold,
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
                              final bool bloqueada = enc['bloqueada'] == true;

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
                                          color: (enc['corEstado'] as Color)
                                              .withValues(alpha: 0.1),
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

                                      // Botão "Iniciar" — desativado enquanto a
                                      // ordem estiver em WIP Hold.
                                      ElevatedButton.icon(
                                        onPressed: bloqueada
                                            ? null
                                            : () async {
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
                                          disabledBackgroundColor: const Color(0xFFE2E8F0),
                                          disabledForegroundColor: const Color(0xFF94A3B8),
                                          minimumSize: const Size.fromHeight(40),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: Icon(
                                          bloqueada ? Icons.lock_outline : Icons.play_arrow,
                                          size: 16,
                                        ),
                                        label: Text(
                                          bloqueada ? 'Aguarda Line Clearance' : 'Iniciar',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
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