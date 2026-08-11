import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/breakpoints.dart';
import '../../core/ecra_recarregavel.dart';
import '../../core/realtime.dart';
import '../../core/temas_cores.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/operador_repository.dart';
import '../../widgets/estado_erro.dart';
import 'detalhe_tarefa_screen.dart';

class FilaTrabalhoScreen extends StatefulWidget {
  const FilaTrabalhoScreen({super.key});

  @override
  State<FilaTrabalhoScreen> createState() => _FilaTrabalhoScreenState();
}

class _FilaTrabalhoScreenState extends State<FilaTrabalhoScreen>
    implements EcraRecarregavel {
  final OperadorRepository _repo = OperadorRepository();
  final EncomendasRepository _encomendasRepo = EncomendasRepository();

  FilaDeTrabalho? _fila;
  bool _aCarregar = true;
  String? _erro;

  RealtimeChannel? _canal;
  late final RecarregadorDebounced _recarregador;

  @override
  void initState() {
    super.initState();
    _recarregador = RecarregadorDebounced(
      aoRecarregar: () => _carregar(mostrarSpinner: false),
    );
    _carregar();

    // A fila é o ecrã operacionalmente mais crítico da aplicação e era o único
    // estático: uma ordem nova no posto, ou um Line Clearance aprovado pelo
    // admin, só apareciam se o operador terminasse sessão.
    _canal = _encomendasRepo.escutarProducao(
      'fila-operador',
      (_) => _recarregador.pedir(),
    );
  }

  @override
  void dispose() {
    _recarregador.descartar();
    final canal = _canal;
    if (canal != null) _encomendasRepo.client.removeChannel(canal);
    super.dispose();
  }

  /// Recarregamento pedido pelo shell ao voltar a este separador.
  @override
  Future<void> recarregar() => _carregar(mostrarSpinner: false);

  /// [mostrarSpinner] fica falso nos recarregamentos vindos do realtime e do
  /// pull-to-refresh: substituir a lista por um spinner a cada evento fazia o
  /// ecrã piscar enquanto o operador está a olhar para ele.
  Future<void> _carregar({bool mostrarSpinner = true}) async {
    if (mostrarSpinner && mounted) {
      setState(() {
        _aCarregar = true;
        _erro = null;
      });
    }

    try {
      final fila = await _repo.obterFila();
      if (!mounted) return;
      setState(() {
        _fila = fila;
        _erro = null;
        _aCarregar = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Um `debugPrint` seguido de lista vazia deixava uma falha de rede
      // indistinguível de "não há trabalho para este posto".
      setState(() {
        _erro = descreverErro(e);
        _aCarregar = false;
      });
    }
  }

  Future<void> _abrirOrdem(OrdemNaFila ordem) async {
    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DetalheTarefaScreen(
          encomendaId: ordem.encomenda.id,
          codigoRastreio: ordem.encomenda.codigoRastreio ?? 'Sem Referência',
        ),
      ),
    );

    if (resultado == true) _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: Padding(
        padding: paddingEcra(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _construirCabecalho(),
            const SizedBox(height: 32),
            Expanded(child: _construirCorpo()),
          ],
        ),
      ),
    );
  }

  Widget _construirCabecalho() {
    final posto = _fila?.posto;

    final titulo = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                TemasCores.operadorAcentoClaro,
                TemasCores.operadorAcentoForte,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.assignment_outlined,
            color: TemasCores.textoInverso,
            size: 26,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ordens de Produção',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.textoPrimarioFrio,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Cartões atribuídos à sua fila de trabalho',
                style: TextStyle(
                  fontSize: 14,
                  color: TemasCores.textoSecundarioFrio,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final acoes = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (posto != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: TemasCores.operadorAcentoFundo,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: TemasCores.operadorAcentoBorda),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.precision_manufacturing_outlined,
                  size: 18,
                  color: TemasCores.operadorAcentoForte,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Posto: ${posto.nome}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: TemasCores.operadorAcentoTextoForte,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: _aCarregar ? null : () => _carregar(),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Recarregar a fila',
          color: TemasCores.operadorAcento,
        ),
      ],
    );

    // Título (28px) + chip de posto + botão não cabem lado a lado num
    // telemóvel — era o único ecrã do terminal do operador sem nenhuma
    // adaptação de cabeçalho, apesar de ser o ecrã inicial do perfil.
    if (context.ehCompacto) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [titulo, const SizedBox(height: 16), acoes],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Flexible(child: titulo), acoes],
    );
  }

  Widget _construirCorpo() {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: TemasCores.operadorAcento),
      );
    }

    final fila = _fila;

    // Só se substitui o ecrã pelo erro quando não há nada carregado. Com a fila
    // já no ecrã, uma falha de rede — que num evento realtime pode ser
    // frequente — não pode fazer desaparecer o trabalho que o operador está a
    // ver: fica uma barra por cima, e os cartões mantêm-se.
    if (_erro != null && fila == null) {
      return EstadoErro(
        titulo: 'Não foi possível carregar a fila de trabalho',
        detalhe: _erro,
        aoRepetir: () => _carregar(),
      );
    }

    final ordens = fila?.ordens ?? const <OrdemNaFila>[];

    return Column(
      children: [
        if (_erro != null)
          EstadoErro.compacto(
            titulo: 'A fila pode estar desatualizada',
            detalhe: _erro,
            aoRepetir: () => _carregar(),
          ),
        // O `RefreshIndicator` precisa de um scrollable que chegue sempre ao
        // topo, por isso a lista vazia também vai dentro de um scrollable.
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _carregar(mostrarSpinner: false),
            child: ordens.isEmpty
                ? _construirVazio(semPosto: fila?.posto == null)
                : _construirGrelha(ordens),
          ),
        ),
      ],
    );
  }

  Widget _construirVazio({required bool semPosto}) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    semPosto ? Icons.person_off_outlined : Icons.inbox_outlined,
                    size: 48,
                    color: TemasCores.textoDesativado,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    semPosto
                        ? 'Nenhum posto de trabalho associado ao seu utilizador.'
                        : 'Não existem ordens de produção pendentes para o seu posto.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: TemasCores.textoTerciario,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirGrelha(List<OrdemNaFila> ordens) {
    final largura = MediaQuery.of(context).size.width;
    final colunas = largura > 1200 ? 3 : (largura > 800 ? 2 : 1);

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: colunas,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        mainAxisExtent: 260,
      ),
      itemCount: ordens.length,
      itemBuilder: (context, index) => _CartaoOrdem(
        ordem: ordens[index],
        aoAbrir: () => _abrirOrdem(ordens[index]),
      ),
    );
  }
}

/// Cartão de uma ordem na fila.
class _CartaoOrdem extends StatelessWidget {
  const _CartaoOrdem({required this.ordem, required this.aoAbrir});

  final OrdemNaFila ordem;
  final VoidCallback aoAbrir;

  /// Etiqueta e cor do cartão.
  ///
  /// O estado de negócio vem de [EstadoOrdem], a definição única partilhada com
  /// o admin. "Atrasado" e "Em Progresso" continuam a existir como leitura
  /// operacional, mas só se aplicam a uma ordem que esteja mesmo em produção:
  /// uma ordem em hold com entrega vencida aparecia como "Atrasado", o que
  /// escondia o motivo real da paragem.
  (String, Color) get _etiqueta {
    if (ordem.bloqueada) {
      return (ordem.estado.etiqueta, TemasCores.acentoRoxo);
    }

    final entrega = ordem.encomenda.dataEntrega;
    final hoje = DateTime.now();
    if (entrega != null &&
        entrega.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) {
      return ('Atrasado', TemasCores.erro);
    }
    if (ordem.progresso > 0) return ('Em Progresso', TemasCores.alertaMedio);
    return ('Pronto a Iniciar', TemasCores.operadorAcentoForte);
  }

  @override
  Widget build(BuildContext context) {
    final (etiqueta, cor) = _etiqueta;
    final percentagem = (ordem.progresso * 100).round();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ordem.encomenda.codigoRastreio ?? 'Sem Referência',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tipo de Produto',
              style: TextStyle(fontSize: 11, color: TemasCores.textoDesativado),
            ),
            Text(
              ordem.encomenda.nomeProduto ?? 'Sem Produto',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: TemasCores.textoApoioForte,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                etiqueta,
                style: TextStyle(
                  color: cor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Progresso Global',
                  style: TextStyle(
                    fontSize: 11,
                    color: TemasCores.textoTerciario,
                  ),
                ),
                Text(
                  '$percentagem%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoApoioForte,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ordem.progresso,
                backgroundColor: TemasCores.bordaForte,
                color: TemasCores.operadorAcento,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: ordem.bloqueada ? null : aoAbrir,
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.operadorAcento,
                foregroundColor: TemasCores.textoInverso,
                disabledBackgroundColor: TemasCores.superficieInerte,
                disabledForegroundColor: TemasCores.textoTerciario,
                minimumSize: const Size.fromHeight(40),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(
                ordem.bloqueada ? Icons.lock_outline : Icons.play_arrow,
                size: 16,
              ),
              label: Text(
                ordem.bloqueada ? 'Aguarda Line Clearance' : 'Iniciar',
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
  }
}
