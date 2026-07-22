import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostosTrabalhoScreen extends StatefulWidget {
  const PostosTrabalhoScreen({Key? key}) : super(key: key);

  @override
  State<PostosTrabalhoScreen> createState() => _PostosTrabalhoScreenState();
}

class _PostosTrabalhoScreenState extends State<PostosTrabalhoScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  List<Map<String, dynamic>> _postos = [];
  List<Map<String, dynamic>> _operadores = [];
  List<Map<String, dynamic>> _encomendasAtivas = [];
  List<Map<String, dynamic>> _incidenciasAtivas = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    try {
      // 1. Carregar Postos de Trabalho
      final postosResponse = await _supabase
          .from('postos_trabalho')
          .select('*, utilizadores:operador_id(utilizador_id, nome_utilizador)')
          .order('id', ascending: true);

      // 2. Carregar APENAS Operadores
      final operadoresResponse = await _supabase
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador')
          .ilike('perfil', 'operador')
          .order('nome_utilizador', ascending: true);

      // 3. Carregar Encomendas em Curso
      final encomendasResponse = await _supabase
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            em_suspenso,
            fase_atual_id,
            clientes!cliente_id(nome_cliente),
            tipos_produto!tipos_produtos_id(nome_tipo_produto),
            fases_padrao!fase_atual_id(id, nome_fase_padrao, posto_trabalho)
          ''');

      // 4. Carregar Incidências Ativas
      final incidenciasResponse = await _supabase
          .from('incidencias')
          .select('''
            id,
            posto_trabalho_id,
            encomenda_id,
            descricao_operador,
            line_clearance_validado,
            reason_codes!reason_code_id(categoria, descricao)
          ''');

      final ordensFiltradas = List<Map<String, dynamic>>.from(encomendasResponse as List? ?? [])
          .where((e) => e['fase_atual_id'] != null)
          .toList();

      final incidenciasFiltradas = List<Map<String, dynamic>>.from(incidenciasResponse as List? ?? [])
          .where((inc) => inc['line_clearance_validado'] != true)
          .toList();

      setState(() {
        _postos = List<Map<String, dynamic>>.from(postosResponse as List? ?? []);
        _operadores = List<Map<String, dynamic>>.from(operadoresResponse as List? ?? []);
        _encomendasAtivas = ordensFiltradas;
        _incidenciasAtivas = incidenciasFiltradas;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar dados: $e'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _obterOrdemAtivaDoPosto(int postoId) {
    for (var enc in _encomendasAtivas) {
      final faseData = enc['fases_padrao'];
      Map<String, dynamic>? fase;

      if (faseData is Map<String, dynamic>) {
        fase = faseData;
      } else if (faseData is List && faseData.isNotEmpty) {
        fase = faseData.first as Map<String, dynamic>?;
      }

      if (fase != null && fase['posto_trabalho'] == postoId) {
        return enc;
      }
    }
    return null;
  }

  Map<String, dynamic>? _obterIncidenciaAtivaDoPosto(int postoId, int? encomendaId) {
    for (var inc in _incidenciasAtivas) {
      final pId = inc['posto_trabalho_id'];
      final eId = inc['encomenda_id'];

      if ((pId != null && pId == postoId) ||
          (encomendaId != null && eId != null && eId == encomendaId)) {
        return inc;
      }
    }
    return null;
  }

  String _extrairMotivoIncidencia(Map<String, dynamic>? inc) {
    if (inc == null) return 'Motivo não especificado';

    final rcData = inc['reason_codes'];
    Map<String, dynamic>? rc;

    if (rcData is Map<String, dynamic>) {
      rc = rcData;
    } else if (rcData is List && rcData.isNotEmpty) {
      rc = rcData.first as Map<String, dynamic>?;
    }

    if (rc != null) {
      final cat = rc['categoria']?.toString() ?? '';
      final desc = rc['descricao']?.toString() ?? '';
      if (cat.isNotEmpty && desc.isNotEmpty) {
        return '[$cat] $desc';
      } else if (desc.isNotEmpty) {
        return desc;
      }
    }

    final descOp = inc['descricao_operador']?.toString();
    if (descOp != null && descOp.trim().isNotEmpty) {
      return descOp;
    }

    return 'Incidência em resolução';
  }

  String _extrairNomeRelacao(dynamic relacaoData, String campoNome, String valorPadrao) {
    if (relacaoData is Map) {
      return relacaoData[campoNome]?.toString() ?? valorPadrao;
    } else if (relacaoData is List && relacaoData.isNotEmpty) {
      return relacaoData.first[campoNome]?.toString() ?? valorPadrao;
    }
    return valorPadrao;
  }

  Future<void> _atualizarOperadorPosto(int postoId, String? novoOperadorId) async {
    try {
      final String? estadoAtual = _postos.firstWhere((p) => p['id'] == postoId)['estado'];
      String novoEstado = estadoAtual ?? 'LIVRE';

      if (novoOperadorId != null && novoEstado == 'LIVRE') {
        novoEstado = 'OCUPADO';
      } else if (novoOperadorId == null && novoEstado == 'OCUPADO') {
        novoEstado = 'LIVRE';
      }

      await _supabase.from('postos_trabalho').update({
        'operador_id': novoOperadorId,
        'estado': novoEstado,
      }).eq('id', postoId);

      _carregarDados();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar operador: $e')),
        );
      }
    }
  }

  Future<void> _alterarEstadoPosto(int postoId, String novoEstado) async {
    try {
      await _supabase.from('postos_trabalho').update({
        'estado': novoEstado,
      }).eq('id', postoId);

      _carregarDados();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao alterar estado: $e')),
        );
      }
    }
  }

  Widget _construirBarraResumo() {
    int totalPostos = _postos.length;
    int postosEmProducao = 0;
    int postosOcupados = 0;
    int postosParados = 0;
    int postosLivres = 0;

    for (var posto in _postos) {
      final String estadoBD = (posto['estado'] ?? 'LIVRE').toString().toUpperCase();
      final String? operadorId = posto['operador_id']?.toString();
      final ordem = _obterOrdemAtivaDoPosto(posto['id']);
      final int? encId = ordem != null ? (ordem['id'] as int?) : null;
      final bool emSuspenso = ordem?['em_suspenso'] == true;
      final inc = _obterIncidenciaAtivaDoPosto(posto['id'], encId);

      final bool estaEmManutencao = estadoBD == 'MANUTENCAO' || estadoBD == 'MANUTENÇÃO';
      final bool temIncidencia = emSuspenso || inc != null || estaEmManutencao;

      if (temIncidencia) {
        postosParados++;
      } else if (ordem != null && operadorId != null) {
        postosEmProducao++;
        postosOcupados++;
      } else if (operadorId != null) {
        postosOcupados++;
      } else {
        postosLivres++;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _construirItemKPI('Total de Postos', '$totalPostos', Icons.factory_outlined, Colors.blue),
          _construirItemKPI('Em Produção', '$postosEmProducao', Icons.play_circle_outline, Colors.green),
          _construirItemKPI('Postos Ocupados', '$postosOcupados', Icons.person_outline, Colors.indigo),
          _construirItemKPI('Parados / WIP Hold', '$postosParados', Icons.warning_amber_rounded, Colors.red),
          _construirItemKPI('Disponíveis / Livres', '$postosLivres', Icons.check_circle_outline, Colors.grey),
        ],
      ),
    );
  }

  Widget _construirItemKPI(String titulo, String valor, IconData icone, Color cor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: cor, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cor)),
            Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
          ],
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão dos Postos de Trabalho'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarDados,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: _postos.isEmpty
                  ? const Center(child: Text('Nenhum posto de trabalho encontrado.'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Barra de KPIs de Supervisão
                        _construirBarraResumo(),

                        // Grelha dos Cards dos Postos
                        Expanded(
                          child: GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 360,
                              mainAxisExtent: 340,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _postos.length,
                            itemBuilder: (context, index) {
                              final posto = _postos[index];
                              final String estadoBD = (posto['estado'] ?? 'LIVRE').toString().toUpperCase();
                              final String? operadorIdAtual = posto['operador_id']?.toString();

                              // Obter a ordem associada
                              final ordemAtiva = _obterOrdemAtivaDoPosto(posto['id']);
                              final int? encomendaId = ordemAtiva != null ? (ordemAtiva['id'] as int?) : null;
                              final bool emSuspenso = ordemAtiva?['em_suspenso'] == true;

                              // Obter incidência ativa
                              final incidenciaAtiva = _obterIncidenciaAtivaDoPosto(posto['id'], encomendaId);
                              final bool estaEmManutencao = estadoBD == 'MANUTENCAO' || estadoBD == 'MANUTENÇÃO';
                              final bool temIncidencia = emSuspenso || incidenciaAtiva != null || estaEmManutencao;

                              // DADOS DO BADGE DINÂMICO
                              String estadoBadge;
                              Color corBadge;

                              if (temIncidencia) {
                                estadoBadge = 'WIP HOLD';
                                corBadge = Colors.red;
                              } else if (ordemAtiva != null && operadorIdAtual != null) {
                                estadoBadge = 'EM PRODUÇÃO';
                                corBadge = Colors.green;
                              } else if (ordemAtiva != null && operadorIdAtual == null) {
                                estadoBadge = 'AGUARDA OPERADOR';
                                corBadge = Colors.orange;
                              } else if (operadorIdAtual != null) {
                                estadoBadge = 'OCUPADO';
                                corBadge = Colors.blue;
                              } else {
                                estadoBadge = 'LIVRE';
                                corBadge = Colors.grey;
                              }

                              // Extração de cliente e produto
                              final String nomeCliente = _extrairNomeRelacao(
                                ordemAtiva?['clientes'],
                                'nome_cliente',
                                'Desconhecido',
                              );
                              final String nomeProduto = _extrairNomeRelacao(
                                ordemAtiva?['tipos_produto'],
                                'nome_tipo_produto',
                                'N/A',
                              );

                              // Validar operador na lista
                              final bool existeNaLista = _operadores.any(
                                (op) => op['utilizador_id'].toString() == operadorIdAtual,
                              );
                              final String? valorValidoDropdown = existeNaLista ? operadorIdAtual : null;

                              return Card(
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: corBadge.withOpacity(0.6),
                                    width: temIncidencia ? 2.5 : 1.5,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Cabeçalho do Card
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              posto['nome_posto'] ?? 'Posto #${posto['id']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: corBadge.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: corBadge),
                                            ),
                                            child: Text(
                                              estadoBadge,
                                              style: TextStyle(
                                                color: corBadge,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 20),

                                      // Seletor de Operador
                                      const Text(
                                        'Operador Atribuído:',
                                        style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<String?>(
                                        value: valorValidoDropdown,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        items: [
                                          const DropdownMenuItem<String?>(
                                            value: null,
                                            child: Text('-- Sem Operador --', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                          ),
                                          ..._operadores.map((op) {
                                            return DropdownMenuItem<String?>(
                                              value: op['utilizador_id'].toString(),
                                              child: Text(op['nome_utilizador'] ?? 'Sem Nome', style: const TextStyle(fontSize: 13)),
                                            );
                                          }).toList(),
                                        ],
                                        onChanged: (novoVal) {
                                          _atualizarOperadorPosto(posto['id'], novoVal);
                                        },
                                      ),

                                      const SizedBox(height: 12),

                                      // BLOCO VISUAL: ORDEM EM CARGA
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: ordemAtiva != null
                                              ? (temIncidencia ? Colors.red.shade50 : Colors.blue.shade50)
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: ordemAtiva != null
                                                ? (temIncidencia ? Colors.red.shade200 : Colors.blue.shade200)
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                        child: ordemAtiva != null
                                            ? Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        'ORD-2026-${ordemAtiva['id'].toString().padLeft(3, '0')}',
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          color: temIncidencia ? Colors.red.shade900 : Colors.blue.shade900,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if (temIncidencia)
                                                        const Text(
                                                          '🚨 WIP HOLD',
                                                          style: TextStyle(
                                                            color: Colors.red,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Cliente: $nomeCliente',
                                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    'Produto: $nomeProduto',
                                                    style: const TextStyle(fontSize: 11, color: Colors.black87),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),

                                                  // Motivo da incidência
                                                  if (temIncidencia) ...[
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                                                          const SizedBox(width: 4),
                                                          Expanded(
                                                            child: Text(
                                                              _extrairMotivoIncidencia(incidenciaAtiva),
                                                              style: const TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.redAccent,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ]
                                                ],
                                              )
                                            : const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(vertical: 6),
                                                  child: Text(
                                                    '-- Sem Ordem em Carga --',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey,
                                                      fontStyle: FontStyle.italic,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),

                                      const Spacer(),

                                      // Ação de Manutenção
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: estaEmManutencao
                                                  ? () => _alterarEstadoPosto(posto['id'], operadorIdAtual != null ? 'OCUPADO' : 'LIVRE')
                                                  : () => _alterarEstadoPosto(posto['id'], 'MANUTENCAO'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: estaEmManutencao ? Colors.green : Colors.red,
                                              ),
                                              child: Text(
                                                estaEmManutencao ? 'Concluir Manutenção' : 'Manutenção Programada',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
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