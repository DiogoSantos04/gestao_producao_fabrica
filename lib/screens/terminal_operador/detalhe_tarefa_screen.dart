import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/breakpoints.dart';
import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/checklist_model.dart';
import '../../models/fase_model.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/encomendas_repository.dart';
import '../../repositories/operador_repository.dart';
import '../../widgets/dialogo_suporte.dart';
import '../../widgets/estado_erro.dart';
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
  final OperadorRepository _repo = OperadorRepository();
  final EncomendasRepository _encomendasRepo = EncomendasRepository();

  DetalheTarefa? _tarefa;
  bool _aCarregar = true;
  String? _erro;

  // --- Andon: cronómetro da fase em curso ---
  Timer? _timerAndon;
  int _segundosDecorridos = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _timerAndon?.cancel();
    super.dispose();
  }

  /// Início do trabalho na fase, registado pelo servidor em
  /// `encomendas.data_inicio_trabalho` quando o operador carrega em "Iniciar".
  ///
  /// Não é `data_inicio_fase`: essa marca a chegada ao posto, e o cronómetro
  /// arrancava com a ordem ainda em fila — chegava ao operador já atrasada.
  DateTime? get _inicioFase => _tarefa?.encomenda.dataInicioTrabalho?.toLocal();

  /// Tempo estimado da fase em curso, em minutos, ou `null` se não estiver
  /// definido no roteiro.
  ///
  /// `FaseModel.tempoEstimado` é 0 quando a coluna vem nula, e 0 não pode ser
  /// tratado como "sem estimativa por omissão de 15 min": isso punha o Andon a
  /// dizer "DENTRO DO PRAZO" para sempre, porque o rácio contra zero nunca
  /// cresce. Sem estimativa, o cartão deixa de fingir que a tem.
  int? get _tempoEstimadoMinutos {
    final tempo = _tarefa?.faseAtual?.tempoEstimado;
    if (tempo == null || tempo <= 0) return null;
    return tempo;
  }

  void _iniciarCronometro() {
    _timerAndon?.cancel();
    _atualizarDecorrido();
    _timerAndon = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_atualizarDecorrido);
    });
  }

  /// Recalcula a partir do início real da fase em vez de somar 1 por tique: um
  /// timer suspenso (ecrã bloqueado, app em segundo plano) deixava o cronómetro
  /// a marcar menos tempo do que o efetivamente decorrido.
  void _atualizarDecorrido() {
    final inicio = _inicioFase;
    final tarefa = _tarefa;
    if (inicio == null || tarefa == null) {
      _segundosDecorridos = 0;
      return;
    }
    final agora = DateTime.now();

    // O tempo que a fase passou parada em WIP Hold não é tempo de produção: sem
    // o descontar, uma avaria de duas horas empurrava o Andon para atraso sem
    // que ninguém tivesse trabalhado devagar. Só conta a paragem posterior ao
    // início do trabalho — ver [DetalheTarefa.tempoParadoEntre].
    final parados = tarefa.tempoParadoEntre(inicio, agora).inSeconds;

    // Os relógios do terminal e do servidor podem divergir; um valor negativo
    // mostraria um cronómetro a contar para trás.
    final decorrido = agora.difference(inicio).inSeconds - parados;
    _segundosDecorridos = decorrido > 0 ? decorrido : 0;
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _aCarregar = true;
      _erro = null;
    });

    _timerAndon?.cancel();

    try {
      final tarefa = await _repo.obterDetalheTarefa(widget.encomendaId);
      if (!mounted) return;
      setState(() {
        _tarefa = tarefa;
        _erro = null;
        _aCarregar = false;
      });

      if (!tarefa.bloqueada && tarefa.encomenda.faseAtualId != null) {
        _iniciarCronometro();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = descreverErro(e);
        _aCarregar = false;
      });
    }
  }

  /// Poka-Yoke: checklist obrigatória antes de concluir a fase.
  ///
  /// Devolve `null` se o operador cancelar. Caso contrário devolve ou os pontos
  /// validados — com a hora a que **cada um** foi marcado, que é o que
  /// distingue uma verificação feita ponto a ponto de uma série de cliques no
  /// fim — ou o ponto que falhou, para abrir incidência.
  Future<_ResultadoChecklist?> _validarChecklist(List<String> itens) async {
    if (itens.isEmpty) return const _ResultadoChecklist.conforme([]);

    // O instante de cada marcação, na posição do respetivo item. `null` é "por
    // marcar": distingue-se de marcado, ao contrário de um `bool` com data à
    // parte, que podia ficar dessincronizado ao desmarcar.
    final marcados = List<DateTime?>.filled(itens.length, null);

    final resultado = await showDialog<_ResultadoChecklist>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final todos = marcados.every((m) => m != null);

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  color: TemasCores.operadorAcentoForte,
                  size: 28,
                ),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Checklist de Qualidade',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirme a validação de todos os pontos de controlo antes '
                  'de encerrar a etapa. Cada marcação fica registada em seu '
                  'nome, com a hora, contra esta ordem.',
                  style: TextStyle(
                    fontSize: 13,
                    color: TemasCores.textoSecundarioFrio,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: List.generate(itens.length, (index) {
                        final marcado = marcados[index] != null;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: marcado
                                ? TemasCores.sucessoFundo
                                : TemasCores.superficieTenue,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: marcado
                                  ? TemasCores.sucessoBorda
                                  : TemasCores.borda,
                            ),
                          ),
                          child: CheckboxListTile(
                            title: Text(
                              itens[index],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: marcado
                                    ? TemasCores.sucessoTexto
                                    : TemasCores.textoPrimario,
                              ),
                            ),
                            value: marcado,
                            activeColor: TemasCores.sucessoForte,
                            // A hora é a da marcação, não a da conclusão da
                            // fase: desmarcar apaga-a para que uma marcação
                            // corrigida não fique com a hora da primeira.
                            onChanged: (val) => setModalState(
                              () => marcados[index] =
                                  (val ?? false) ? DateTime.now() : null,
                            ),
                            // O ponto que falha não fecha a fase: encaminha
                            // para a incidência. Sem esta saída, um operador
                            // com um ponto não conforme e a linha à espera
                            // acaba por marcar tudo à mesma — o Poka-Yoke
                            // ensinaria precisamente o contrário do que existe
                            // para garantir.
                            secondary: IconButton(
                              tooltip: 'Ponto não conforme — reportar',
                              icon: const Icon(
                                Icons.report_problem_outlined,
                                size: 20,
                                color: TemasCores.erro,
                              ),
                              onPressed: () => Navigator.pop(
                                context,
                                _ResultadoChecklist.naoConforme(itens[index]),
                              ),
                            ),
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
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: todos
                    ? () => Navigator.pop(
                          context,
                          _ResultadoChecklist.conforme([
                            for (var i = 0; i < itens.length; i++)
                              PontoValidado(
                                posicao: i,
                                item: itens[i],
                                marcadoEm: marcados[i]!,
                              ),
                          ]),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemasCores.sucessoForte,
                  foregroundColor: TemasCores.textoInverso,
                  disabledBackgroundColor: TemasCores.superficieInerte,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Validar & Concluir Fase'),
              ),
            ],
          );
        },
      ),
    );

    return resultado;
  }

  /// Pede a validação necessária e, se passar, fecha a fase.
  ///
  /// A checklist e a confirmação não se somam: quem acabou de marcar os pontos
  /// de controlo um a um e carregou em "Validar & Concluir Fase" já confirmou
  /// de forma bem mais deliberada do que um "tem a certeza?" acrescentaria.
  /// Encadear os dois diálogos só ensinava o operador a despachá-los sem ler —
  /// que é exatamente o que a confirmação existe para evitar. A confirmação
  /// serve as fases **sem** checklist, onde de outro modo bastava um toque.
  Future<void> _solicitarConclusaoFase() async {
    final fase = _tarefa?.faseAtual;
    if (fase == null) return;

    if (fase.checklist.isEmpty) {
      final confirmado = await _confirmarConclusao(fase);
      if (!confirmado || !mounted) return;
      return _concluirFase(fase, const []);
    }

    final resultado = await _validarChecklist(fase.checklist);
    if (resultado == null || !mounted) return;

    // Um ponto de controlo não conforme é uma paragem de linha, não uma fase
    // concluída: o operador segue direto para a incidência, com o ponto que
    // falhou já escrito na descrição.
    final falhou = resultado.itemNaoConforme;
    if (falhou != null) {
      return _abrirPopupIncidencia(
        descricaoInicial: 'Ponto de controlo não conforme: $falhou',
      );
    }

    await _concluirFase(fase, resultado.pontos);
  }

  /// Transição de fase pela RPC transacional `avancar_fase_encomenda`.
  ///
  /// Antes, o ecrã fazia duas escritas separadas — `insert` em
  /// `historico_producao` seguido de `update` em `encomendas` — e decidia em
  /// Dart qual era a fase seguinte ("índice + 1"). Uma falha entre as duas
  /// deixava um registo de histórico órfão com a ordem parada na mesma fase, e
  /// a regra duplicada podia divergir da do servidor. Ver bug (A) em
  /// docs/AlteracoesNoOperador.md.
  ///
  /// A RPC decide a fase seguinte, escreve o histórico e atualiza a ordem numa
  /// só transação, e recusa o avanço se a ordem estiver em WIP Hold ou
  /// cancelada — validações que o cliente não pode garantir sozinho.
  /// [pontos] são os pontos de controlo que o operador validou. Vão na mesma
  /// chamada porque a RPC os grava dentro da transação do avanço: a prova de
  /// conformidade e a fase fechada existem ambas, ou nenhuma existe.
  Future<void> _concluirFase(FaseModel fase, List<PontoValidado> pontos) async {
    setState(() => _aCarregar = true);
    _timerAndon?.cancel();

    try {
      final resultado = await _encomendasRepo.avancarFase(
        widget.encomendaId,
        checklist: pontos,
      );
      if (!mounted) return;

      final concluida = resultado['concluida'] == true;
      final proxima = resultado['proxima_fase_nome']?.toString();

      context.mostrarMensagem(
        concluida
            ? 'Etapa concluída — ordem finalizada.'
            : proxima != null
                ? 'Etapa concluída. Ordem avançou para: $proxima'
                : 'Etapa concluída com sucesso.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // As RPCs de produção lançam mensagens de negócio já escritas em
      // português (ex: "Encomenda em WIP Hold: aprove o Line Clearance antes
      // de avançar."). São mostradas tal e qual ao operador.
      context.mostrarMensagem(_mensagemDeErro(e), eErro: true);

      // O estado no servidor pode ter mudado (hold aplicado por outra via,
      // ordem cancelada): recarregar evita que o operador continue a olhar
      // para uma fase que já não é a atual.
      _carregar();
    }
  }

  /// Confirmação antes de fechar a fase.
  ///
  /// A conclusão é irreversível pelo terminal — não há como recuar uma fase sem
  /// intervenção do admin — e o botão fica ao lado de "Reportar Incidência",
  /// num ecrã operado com luvas.
  Future<bool> _confirmarConclusao(FaseModel fase) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Concluir a fase?'),
        content: Text(
          'A fase "${fase.nomeFasePadrao}" da ordem ${widget.codigoRastreio} '
          'passa a concluída e a ordem avança no roteiro.\n\n'
          'Esta ação não pode ser desfeita no terminal.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.sucessoForte,
              foregroundColor: TemasCores.textoInverso,
            ),
            child: const Text('Concluir fase'),
          ),
        ],
      ),
    );

    return confirmado == true;
  }

  String _mensagemDeErro(Object e) {
    if (e is RepositoryException) return e.mensagem;
    return descreverErro(e);
  }

  /// [descricaoInicial] pré-preenche as observações — usado quando a incidência
  /// nasce de um ponto de controlo não conforme, para o operador não ter de
  /// reescrever à mão o que acabou de assinalar.
  Future<void> _abrirPopupIncidencia({String? descricaoInicial}) async {
    final faseAtualId = _tarefa?.encomenda.faseAtualId;
    if (faseAtualId == null) return;

    _timerAndon?.cancel();

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => BloquearTarefaPopup(
        encomendaId: widget.encomendaId,
        codigoRastreio: widget.codigoRastreio,
        faseAtualId: faseAtualId,
        descricaoInicial: descricaoInicial,
      ),
    );

    if (resultado == true) {
      _carregar();
    } else {
      _iniciarCronometro();
    }
  }

  /// Mostra o email do administrador, com o código de rastreio da ordem já no
  /// assunto — equivalente ao "Contactar Suporte" do portal do cliente, agora
  /// do lado do operador. O diálogo é partilhado com o resto da app
  /// ([mostrarDialogoSuporte]).
  void _contactarAdministrador() {
    mostrarDialogoSuporte(
      context,
      aoObterEmail: _repo.obterEmailSuporte,
      titulo: 'Contactar Administrador',
      descricao: 'Contacte o administrador para dúvidas ou problemas relacionados com esta ordem.',
      rotuloEmail: 'Email do Administrador',
      corAcento: TemasCores.operadorAcento,
      codigoRastreio: widget.codigoRastreio,
      assunto: 'Terminal Operador - Ordem ${widget.codigoRastreio}',
    );
  }

  static String _formatarTempo(int totalSegundos) {
    final d = Duration(seconds: totalSegundos);
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(d.inHours)}:${d2(d.inMinutes % 60)}:${d2(d.inSeconds % 60)}';
  }

  static String _formatarData(DateTime? d) {
    if (d == null) return '—';
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(d.day)}/${d2(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      appBar: AppBar(
        title: Text(
          widget.codigoRastreio,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: TemasCores.textoPrimario,
          ),
        ),
        elevation: 0,
        backgroundColor: TemasCores.superficie,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TemasCores.textoPrimario),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded, color: TemasCores.operadorAcento),
            tooltip: 'Contactar Administrador',
            onPressed: _contactarAdministrador,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _construirCorpo(),
    );
  }

  Widget _construirCorpo() {
    if (_aCarregar) {
      return const Center(
        child: CircularProgressIndicator(color: TemasCores.operadorAcento),
      );
    }

    final tarefa = _tarefa;
    if (_erro != null || tarefa == null) {
      // A ordem não carregou: não há nada de fiável para mostrar, e mostrar um
      // ecrã meio preenchido num posto de trabalho é pior do que não mostrar.
      return EstadoErro(
        titulo: 'Não foi possível carregar esta ordem',
        detalhe: _erro,
        aoRepetir: _carregar,
      );
    }

    return Padding(
      padding: paddingEcra(context),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                    Icons.precision_manufacturing_outlined,
                    color: TemasCores.textoInverso,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.codigoRastreio,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.textoPrimarioFrio,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Produto: ${tarefa.encomenda.nomeProduto ?? 'Artigo'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: TemasCores.textoSecundarioFrio,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (tarefa.bloqueada)
              _construirAvisoBloqueio(tarefa)
            else if (tarefa.faseForaDoRoteiro)
              _construirAvisoFaseDesconhecida()
            else if (tarefa.encomenda.faseAtualId != null)
              _construirCardAndon(),
            const SizedBox(height: 24),
            // Abaixo do breakpoint médio a coluna de fases não cabe ao lado do
            // resto sem espremer os dois: passa a empilhar, fases por último.
            if (context.ehAmplo)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _construirColunaEsquerda(tarefa)),
                  const SizedBox(width: 32),
                  Expanded(flex: 2, child: _construirCardFases(tarefa)),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _construirColunaEsquerda(tarefa),
                  const SizedBox(height: 24),
                  _construirCardFases(tarefa),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// A ordem está numa fase que não pertence ao roteiro do produto.
  ///
  /// Acontece quando o roteiro é alterado depois de a ordem ter sido lançada.
  /// O ecrã não consegue dizer em que passo a ordem está, nem quanto tempo essa
  /// fase devia demorar, por isso não mostra o cronómetro e não deixa concluir:
  /// fechar a fase errada é pior do que ter de chamar a supervisão.
  Widget _construirAvisoFaseDesconhecida() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TemasCores.avisoFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.avisoBorda),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, color: TemasCores.avisoTextoForte),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fase atual não reconhecida',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: TemasCores.avisoTextoForte,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'A fase em que esta ordem se encontra não pertence ao '
                  'roteiro do produto — o roteiro terá sido alterado depois de '
                  'a ordem ser lançada. Contacte a supervisão antes de '
                  'continuar.',
                  style: TextStyle(
                    fontSize: 13,
                    color: TemasCores.textoApoioForte,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Porque é que a ordem não pode ser trabalhada.
  ///
  /// Antes, uma ordem bloqueada limitava-se a apresentar os botões desativados,
  /// sem dizer porquê: quem chega ao posto não tinha como saber se era um
  /// bloqueio, um erro, ou a ordem já estar concluída.
  Widget _construirAvisoBloqueio(DetalheTarefa tarefa) {
    final aberta = tarefa.incidencias.where((i) => i.estaAberta).toList();
    final motivos = aberta.map((i) => i.rotulo).whereType<String>().toSet();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: TemasCores.acentoRoxoFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.acentoRoxo),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, color: TemasCores.acentoRoxoForte),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ordem em WIP Hold',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: TemasCores.acentoRoxoForte,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  motivos.isEmpty
                      ? 'A produção está suspensa. Aguarda aprovação do Line '
                          'Clearance no painel do admin.'
                      : 'Motivo: ${motivos.join(' • ')}\nAguarda aprovação do '
                          'Line Clearance no painel do admin.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: TemasCores.textoApoioForte,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirColunaEsquerda(DetalheTarefa tarefa) {
    final encomenda = tarefa.encomenda;
    final observacoes = encomenda.observacoes?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          color: TemasCores.superficie,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: TemasCores.borda),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Especificações Técnicas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoPrimario,
                  ),
                ),
                const SizedBox(height: 16),
                // "Dimensões: 500mm x 300mm x 150mm" e "Material: Aço
                // Inoxidável 304" estavam escritos no código: dados falsos
                // mostrados ao operador no posto. O schema não guarda dimensões
                // nem material, pelo que se mostram os campos que a ordem tem
                // mesmo.
                _Especificacao(
                  rotulo: 'Quantidade:',
                  valor: '${encomenda.quantidade}',
                ),
                const Divider(height: 24),
                _Especificacao(
                  rotulo: 'Prioridade:',
                  valor: encomenda.prioridade,
                ),
                const Divider(height: 24),
                _Especificacao(
                  rotulo: 'Data de Entrega:',
                  valor: _formatarData(encomenda.dataEntrega),
                ),
                const Divider(height: 24),
                _Especificacao(
                  rotulo: 'Tempo Estimado da Fase:',
                  valor: _tempoEstimadoMinutos == null
                      ? '—'
                      : '$_tempoEstimadoMinutos min',
                ),
                if (observacoes != null && observacoes.isNotEmpty) ...[
                  const Divider(height: 24),
                  _Especificacao(rotulo: 'Observações:', valor: observacoes),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: tarefa.bloqueada || tarefa.faseAtual == null
                    ? null
                    : _solicitarConclusaoFase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TemasCores.sucessoForte,
                  foregroundColor: TemasCores.textoInverso,
                  disabledBackgroundColor: TemasCores.superficieInerte,
                  disabledForegroundColor: TemasCores.textoTerciario,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  'Concluir Fase',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: tarefa.bloqueada ? null : _abrirPopupIncidencia,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TemasCores.erroForte,
                  side: const BorderSide(color: TemasCores.erroClaro),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: const Text(
                  'Reportar Incidência',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _construirCardAndon() {
    final estimado = _tempoEstimadoMinutos;

    // Sem estimativa não há prazo a comparar: o cartão conta o tempo, mas não
    // afirma que está dentro de nada.
    Color cor = TemasCores.infoForte;
    String estado = 'SEM TEMPO ESTIMADO';

    if (_inicioFase == null) {
      // Sem início registado não há tempo decorrido a avaliar: dizer "DENTRO
      // DO PRAZO" com o relógio parado seria afirmar algo que não se mediu.
      estado = 'TRABALHO NÃO INICIADO';
    } else if (estimado != null) {
      final racio = _segundosDecorridos / (estimado * 60);
      if (racio > 1.0) {
        cor = TemasCores.erroForte;
        estado = 'TEMPO ESTIMADO EXCEDIDO';
      } else if (racio >= 0.8) {
        cor = TemasCores.aviso;
        estado = 'ATENÇÃO AO LIMITE';
      } else {
        cor = TemasCores.sucessoForte;
        estado = 'DENTRO DO PRAZO';
      }
    }

    return Card(
      elevation: 0,
      color: cor.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
              child: const Icon(
                Icons.timer_outlined,
                color: TemasCores.textoInverso,
                size: 28,
              ),
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
                        estado,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: cor,
                        ),
                      ),
                      Text(
                        estimado == null
                            ? 'Estimativa não definida'
                            : 'Estimado: $estimado min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TemasCores.textoSecundarioFrio,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _inicioFase == null
                        ? '--:--:--'
                        : _formatarTempo(_segundosDecorridos),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: cor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirCardFases(DetalheTarefa tarefa) {
    return Card(
      elevation: 0,
      color: TemasCores.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Fases de Produção',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TemasCores.textoPrimario,
              ),
            ),
            const SizedBox(height: 24),
            _construirTimeline(tarefa),
          ],
        ),
      ),
    );
  }

  Widget _construirTimeline(DetalheTarefa tarefa) {
    if (tarefa.fases.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'Nenhuma fase configurada para este produto.',
          style: TextStyle(
            fontSize: 13,
            color: TemasCores.textoTerciario,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    final faseAtual = tarefa.faseAtual;
    final indiceAtual = faseAtual == null
        ? -1
        : tarefa.fases.indexWhere((f) => f.id == faseAtual.id);

    // Distinguem-se dois casos que dão ambos `indiceAtual == -1`: a ordem
    // percorreu o roteiro todo (não há fase atual), ou a fase atual não
    // pertence a este roteiro. No segundo, marcar tudo como concluído seria
    // afirmar que a ordem acabou — não sabemos onde está.
    final ordemConcluida = tarefa.encomenda.faseAtualId == null;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tarefa.fases.length,
      itemBuilder: (context, index) {
        final fase = tarefa.fases[index];

        final concluida =
            ordemConcluida || (indiceAtual >= 0 && index < indiceAtual);
        final atual = indiceAtual >= 0 && index == indiceAtual;

        return _PassoTimeline(
          numero: index + 1,
          nome: fase.nomeFasePadrao.isEmpty
              ? 'Fase #${index + 1}'
              : fase.nomeFasePadrao,
          concluida: concluida,
          atual: atual,
          ultima: index == tarefa.fases.length - 1,
        );
      },
    );
  }
}

/// Uma linha `rótulo — valor` do cartão de especificações.
class _Especificacao extends StatelessWidget {
  const _Especificacao({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: const TextStyle(
            color: TemasCores.textoSecundarioFrio,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: TemasCores.textoPrimario,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

/// Um passo do roteiro na coluna da direita.
class _PassoTimeline extends StatelessWidget {
  const _PassoTimeline({
    required this.numero,
    required this.nome,
    required this.concluida,
    required this.atual,
    required this.ultima,
  });

  final int numero;
  final String nome;
  final bool concluida;
  final bool atual;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    final corMarca = concluida
        ? TemasCores.sucessoForte
        : (atual ? TemasCores.operadorAcentoClaro : TemasCores.superficieSuave);

    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: corMarca,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: concluida || atual
                        ? Colors.transparent
                        : TemasCores.bordaForte,
                  ),
                ),
                child: Center(
                  child: concluida
                      ? const Icon(
                          Icons.check,
                          color: TemasCores.textoInverso,
                          size: 16,
                        )
                      : Text(
                          '$numero',
                          style: TextStyle(
                            color: atual
                                ? TemasCores.textoInverso
                                : TemasCores.textoTerciario,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              if (!ultima)
                Expanded(
                  child: Container(
                    width: 2,
                    color: concluida
                        ? TemasCores.sucessoForte
                        : TemasCores.borda,
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
                    fontWeight: atual ? FontWeight.bold : FontWeight.w500,
                    color: atual
                        ? TemasCores.textoPrimario
                        : (concluida
                            ? TemasCores.textoSecundarioFrio
                            : TemasCores.textoDesativado),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  concluida
                      ? 'Concluída'
                      : (atual ? 'Em andamento...' : 'Aguardando'),
                  style: TextStyle(
                    fontSize: 11,
                    color: concluida
                        ? TemasCores.sucessoForte
                        : (atual
                            ? TemasCores.operadorAcentoClaro
                            : TemasCores.textoDesativado),
                    fontWeight: atual ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// O que saiu do diálogo da checklist Poka-Yoke.
///
/// São dois desfechos e não um `bool`: ou os pontos foram todos validados — e
/// nesse caso interessa **quais** e a que horas, porque é isso que fica gravado
/// como prova de conformidade —, ou um deles falhou e a fase não fecha.
/// Cancelar é a ausência de resultado (`null`), não um terceiro caso.
class _ResultadoChecklist {
  /// Pontos validados, por ordem da checklist da fase. Vazio quando falhou.
  final List<PontoValidado> pontos;

  /// O ponto que o operador marcou como não conforme, se houve algum.
  final String? itemNaoConforme;

  const _ResultadoChecklist.conforme(this.pontos) : itemNaoConforme = null;

  const _ResultadoChecklist.naoConforme(String item)
      : pontos = const [],
        itemNaoConforme = item;
}
