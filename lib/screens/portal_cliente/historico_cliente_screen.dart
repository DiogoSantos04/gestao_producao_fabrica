import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/pdf_service.dart';

class HistoricoClienteScreen extends StatefulWidget {
  final Function(int tipoProdutoId, int quantidade)? onRepetirEncomenda;

  const HistoricoClienteScreen({super.key, this.onRepetirEncomenda});

  @override
  State<HistoricoClienteScreen> createState() => _HistoricoClienteScreenState();
}

class _HistoricoClienteScreenState extends State<HistoricoClienteScreen> {
  final _supabase = Supabase.instance.client;
  List<dynamic> _encomendasCliente = [];
  Set<int> _encomendasAvaliadasIds = {};
  bool _isLoading = true;
  String? _erro;
  int? _clienteId;
  String _nomeCliente = 'Cliente';

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  Future<void> _carregarHistorico() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() { _erro = 'Utilizador não autenticado.'; _isLoading = false; });
        return;
      }

      final utilizadorData = await _supabase
          .from('utilizadores')
          .select('nome_utilizador')
          .eq('utilizador_id', user.id)
          .maybeSingle();

      if (utilizadorData == null) {
        if (mounted) setState(() { _erro = 'Perfil não encontrado.'; _isLoading = false; });
        return;
      }

      _nomeCliente = utilizadorData['nome_utilizador']?.toString() ?? 'Cliente';

      final clienteData = await _supabase
          .from('clientes')
          .select('id')
          .eq('nome_cliente', _nomeCliente)
          .maybeSingle();

      if (clienteData == null) {
        if (mounted) setState(() { _encomendasCliente = []; _isLoading = false; });
        return;
      }

      _clienteId = clienteData['id'] is int ? clienteData['id'] : int.parse(clienteData['id'].toString());

      final encomendasData = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            quantidade,
            tipos_produto ( nome_tipo_produto ),
            fases_padrao!fase_atual_id ( nome_fase_padrao )
          ''')
          .eq('cliente_id', _clienteId!)
          .order('created_at', ascending: false);

      final avaliacoesData = await _supabase
          .from('avaliacoes')
          .select('encomenda_id')
          .eq('cliente_id', _clienteId!);

      final Set<int> idsAvaliados = (avaliacoesData as List)
          .map((a) => a['encomenda_id'] is int ? a['encomenda_id'] as int : int.parse(a['encomenda_id'].toString()))
          .toSet();

      if (mounted) {
        setState(() {
          _encomendasCliente = encomendasData;
          _encomendasAvaliadasIds = idsAvaliados;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar histórico: $e');
      if (mounted) {
        setState(() {
          _erro = 'Não foi possível carregar o histórico de encomendas.';
          _isLoading = false;
        });
      }
    }
  }

  void _mostrarDialogoAvaliacao(Map<String, dynamic> enc) {
    int notaSelecionada = 5;
    final comentarioController = TextEditingController();
    bool enviando = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Avaliar ${enc['codigo_rastreio']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Como avalia a qualidade de fabrico e o cumprimento do prazo?',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final estrelaIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          estrelaIndex <= notaSelecionada ? Icons.star_rounded : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() => notaSelecionada = estrelaIndex);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: comentarioController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comentário / Sugestão (opcional)',
                      border: OutlineInputBorder(),
                      hintText: 'Escreva a sua opinião sobre o produto entregue...',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: enviando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: enviando
                      ? null
                      : () async {
                          setDialogState(() => enviando = true);
                          try {
                            final int encId = enc['id'] is int ? enc['id'] : int.parse(enc['id'].toString());

                            // Envia '' em vez de null caso esteja vazio, resolvendo a restrição NOT NULL
                            final String textoComentario = comentarioController.text.trim();

                            await _supabase.from('avaliacoes').insert({
                              'encomenda_id': encId,
                              'cliente_id': _clienteId,
                              'nota': notaSelecionada,
                              'comentario': textoComentario,
                              'data_registo': DateTime.now().toIso8601String().split('T').first,
                            });

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Agradecemos a sua avaliação! ⭐'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _carregarHistorico();
                            }
                          } catch (e) {
                            debugPrint('Erro ao guardar avaliação: $e');
                            setDialogState(() => enviando = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Erro ao submeter: $e'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submeter Avaliação'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatarData(String? isoString) {
    if (isoString == null) return 'A definir';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(_erro!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(40.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Histórico de Encomendas',
                                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Consulte todas as suas encomendas, avalie a qualidade, repita um pedido ou baixe o certificado.',
                                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () {
                              setState(() => _isLoading = true);
                              _carregarHistorico();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      Expanded(
                        child: _encomendasCliente.isEmpty
                            ? const Center(
                                child: Text('Ainda não tem encomendas registadas.', style: TextStyle(color: Colors.grey)),
                              )
                            : ListView.builder(
                                itemCount: _encomendasCliente.length,
                                itemBuilder: (context, index) {
                                  final enc = _encomendasCliente[index];
                                  final int encId = enc['id'] is int ? enc['id'] : int.parse(enc['id'].toString());
                                  final produto = enc['tipos_produto']?['nome_tipo_produto'] ?? 'Artigo';

                                  final bool temFaseAtual = enc['fase_atual_id'] != null;
                                  final String? faseNome = enc['fases_padrao']?['nome_fase_padrao'];

                                  final bool eFinalizado = !temFaseAtual ||
                                      (faseNome != null && (
                                          faseNome.toLowerCase().contains('concluí') ||
                                          faseNome.toLowerCase().contains('finaliz') ||
                                          faseNome.toLowerCase().contains('entregue')
                                      ));

                                  final String estadoTexto = eFinalizado
                                      ? 'CONCLUÍDO'
                                      : (faseNome?.toUpperCase() ?? 'EM PRODUÇÃO');

                                  final bool jaAvaliado = _encomendasAvaliadasIds.contains(encId);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.grey.shade200),
                                    ),
                                    color: Colors.white,
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: eFinalizado ? Colors.green.shade50 : Colors.deepPurple.shade50,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              eFinalizado ? Icons.task_alt_rounded : Icons.receipt_long,
                                              color: eFinalizado ? Colors.green : Colors.deepPurple,
                                              size: 24,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      enc['codigo_rastreio'] ?? 'Sem Código',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: eFinalizado ? Colors.green.shade100 : Colors.blue.shade100,
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text(
                                                        estadoTexto,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: eFinalizado ? Colors.green.shade900 : Colors.blue.shade900,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Artigo: $produto (${enc['quantidade'] ?? 1} unid.)',
                                                  style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w500),
                                                ),
                                                Text(
                                                  'Data de Entrega: ${_formatarData(enc['data_entrega'])}',
                                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Botões de Ação do Cliente
                                          Row(
                                            children: [
                                              if (eFinalizado) ...[
                                                IconButton(
                                                  icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
                                                  tooltip: 'Certificado de Conformidade PDF',
                                                  onPressed: () {
                                                    PdfService.descarregarCertificadoConformidade(
                                                      codigoRastreio: enc['codigo_rastreio'] ?? 'N/A',
                                                      nomeCliente: _nomeCliente,
                                                      nomeProduto: produto,
                                                      quantidade: enc['quantidade'] ?? 1,
                                                      dataEntrega: _formatarData(enc['data_entrega']),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 8),

                                                if (jaAvaliado)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    decoration: BoxDecoration(
                                                      color: Colors.amber.shade50,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: const Row(
                                                      children: [
                                                        Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                                        SizedBox(width: 4),
                                                        Text('Avaliado', style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  )
                                                else
                                                  OutlinedButton.icon(
                                                    onPressed: () => _mostrarDialogoAvaliacao(enc),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.amber.shade900,
                                                      side: BorderSide(color: Colors.amber.shade300),
                                                    ),
                                                    icon: const Icon(Icons.star_outline_rounded, size: 18),
                                                    label: const Text('Avaliar'),
                                                  ),
                                                const SizedBox(width: 12),
                                              ],

                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  final int tipoId = enc['tipos_produtos_id'] is int
                                                      ? enc['tipos_produtos_id']
                                                      : int.parse(enc['tipos_produtos_id'].toString());
                                                  final int qtd = enc['quantidade'] ?? 1;

                                                  if (widget.onRepetirEncomenda != null) {
                                                    widget.onRepetirEncomenda!(tipoId, qtd);
                                                  }
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.deepPurple,
                                                  foregroundColor: Colors.white,
                                                ),
                                                icon: const Icon(Icons.replay_rounded, size: 16),
                                                label: const Text('Repetir Pedido'),
                                              ),
                                            ],
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