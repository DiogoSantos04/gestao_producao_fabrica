import 'package:flutter/material.dart';
import '../../core/formatos.dart';
import '../../models/encomenda_model.dart';
import '../../models/incidencia_model.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/postos_repository.dart';
import '../../repositories/utilizadores_repository.dart';

class PostosTrabalhoScreen extends StatefulWidget {
  const PostosTrabalhoScreen({super.key});

  @override
  State<PostosTrabalhoScreen> createState() => _PostosTrabalhoScreenState();
}

class _PostosTrabalhoScreenState extends State<PostosTrabalhoScreen> {
  final _postosRepo = PostosRepository();
  final _encomendasRepo = EncomendasRepository();
  final _utilizadoresRepo = UtilizadoresRepository();
  bool _isLoading = true;

  List<Map<String, dynamic>> _postos = [];
  List<Map<String, dynamic>> _operadores = [];
  List<EncomendaModel> _encomendasAtivas = [];
  List<IncidenciaModel> _incidenciasAtivas = [];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  Future<void> _carregarDados() async {
    setState(() => _isLoading = true);
    try {
      // Tipos diferentes por chamada, pelo que aguardamos cada uma
      // explicitamente em vez de um Future.wait heterogéneo.
      final postos = await _postosRepo.obterTodos();
      final operadores = await _utilizadoresRepo.obterOperadores();
      final ordens = await _encomendasRepo.obterEmCursoPorPosto();
      final incidencias = await _encomendasRepo.obterIncidenciasPorPosto();

      if (!mounted) return;
      setState(() {
        _postos = postos;
        _operadores = operadores;
        _encomendasAtivas = ordens;
        _incidenciasAtivas = incidencias;
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

  /// Liga a ordem ao posto pela chave estrangeira `fases_padrao.posto_trabalho_id`.
  /// Antes comparava-se o nome do posto em texto livre, o que nunca casava para
  /// as fases criadas a partir do catálogo hardcoded ("Posto de Lixagem", etc.).
  EncomendaModel? _obterOrdemAtivaDoPosto(int postoId) {
    for (final enc in _encomendasAtivas) {
      if (enc.postoFaseAtualId == postoId) return enc;
    }
    return null;
  }

  IncidenciaModel? _obterIncidenciaAtivaDoPosto(int postoId, int? encomendaId) {
    for (final inc in _incidenciasAtivas) {
      final pId = inc.postoTrabalhoId;
      final eId = inc.encomendaId;

      if ((pId != null && pId == postoId) ||
          (encomendaId != null && eId != null && eId == encomendaId)) {
        return inc;
      }
    }
    return null;
  }

  String _extrairMotivoIncidencia(IncidenciaModel? inc) {
    if (inc == null) return 'Motivo não especificado';

    final cat = inc.categoriaReasonCode ?? '';
    final desc = inc.descricaoReasonCode ?? '';
    if (cat.isNotEmpty && desc.isNotEmpty) return '[$cat] $desc';
    if (desc.isNotEmpty) return desc;

    final descOp = inc.descricaoOperador;
    if (descOp != null && descOp.trim().isNotEmpty) return descOp;

    return 'Incidência em resolução';
  }

  Future<void> _atualizarOperadorPosto(int postoId, String? novoOperadorId) async {
    try {
      final String estadoAtual =
          (_postos.firstWhere((p) => p['id'] == postoId)['estado'] ?? EstadoPosto.livre).toString();

      // Um posto em manutenção mantém-se parado independentemente do operador.
      String novoEstado = estadoAtual;
      if (estadoAtual != EstadoPosto.parado) {
        final bool temOrdem = _obterOrdemAtivaDoPosto(postoId) != null;
        novoEstado = (novoOperadorId != null && temOrdem)
            ? EstadoPosto.emProducao
            : EstadoPosto.livre;
      }

      await _postosRepo.atribuirOperador(
        postoId: postoId,
        operadorId: novoOperadorId,
        estado: novoEstado,
      );

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
      await _postosRepo.alterarEstado(postoId: postoId, estado: novoEstado);
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
      final String estadoBD = (posto['estado'] ?? EstadoPosto.livre).toString();
      final String? operadorId = posto['operador_id']?.toString();
      final int postoId = posto['id'] as int;

      final ordem = _obterOrdemAtivaDoPosto(postoId);
      final bool emSuspenso = ordem?.emSuspenso == true;
      final inc = _obterIncidenciaAtivaDoPosto(postoId, ordem?.id);

      final bool estaEmManutencao = estadoBD == EstadoPosto.parado;
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
                              final String estadoBD = (posto['estado'] ?? EstadoPosto.livre).toString();
                              final String? operadorIdAtual = posto['operador_id']?.toString();
                              final int postoId = posto['id'] as int;

                              // Obter a ordem associada pela ligação real (FK)
                              final ordemAtiva = _obterOrdemAtivaDoPosto(postoId);
                              final bool emSuspenso = ordemAtiva?.emSuspenso == true;

                              // Obter incidência ativa
                              final incidenciaAtiva =
                                  _obterIncidenciaAtivaDoPosto(postoId, ordemAtiva?.id);
                              final bool estaEmManutencao = estadoBD == EstadoPosto.parado;
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

                              // Cliente e produto: o modelo já desembrulha as junções
                              final String nomeCliente = ordemAtiva?.nomeCliente ?? 'Desconhecido';
                              final String nomeProduto = ordemAtiva?.nomeProduto ?? 'N/A';

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
                                                        ordemAtiva.codigoRastreio ??
                                                            Formatos.referenciaOrdem(
                                                              ordemAtiva.id,
                                                              criadaEm: ordemAtiva.createdAt
                                                                  ?.toIso8601String(),
                                                            ),
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
                                                  ? () => _alterarEstadoPosto(
                                                        postoId,
                                                        (operadorIdAtual != null && ordemAtiva != null)
                                                            ? EstadoPosto.emProducao
                                                            : EstadoPosto.livre,
                                                      )
                                                  : () => _alterarEstadoPosto(postoId, EstadoPosto.parado),
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