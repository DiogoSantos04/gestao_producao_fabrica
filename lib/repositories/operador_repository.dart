import '../core/paginacao.dart';
import '../models/encomenda_model.dart';
import '../models/estado_ordem.dart';
import '../models/fase_model.dart';
import '../models/historico_model.dart';
import '../models/incidencia_model.dart';
import 'base_repository.dart';

/// Posto de trabalho atribuído ao operador com sessão iniciada.
class PostoDoOperador {
  final int id;
  final String nome;

  const PostoDoOperador({required this.id, required this.nome});
}

/// Uma ordem tal como aparece no cartão da fila de trabalho.
class OrdemNaFila {
  final EncomendaModel encomenda;

  /// Fração do roteiro já percorrida, entre 0.0 e 1.0.
  final double progresso;

  const OrdemNaFila({required this.encomenda, required this.progresso});

  EstadoOrdem get estado => encomenda.estado;

  /// Uma ordem em WIP Hold continua visível — escondê-la deixaria o operador
  /// sem saber para onde foi o trabalho —, mas não pode ser iniciada até o
  /// Line Clearance ser aprovado. Ver bug (E) em docs/AlteracoesNoOperador.md.
  bool get bloqueada => estado == EstadoOrdem.emHold;
}

/// O que o ecrã da fila precisa de mostrar, incluindo o caso "sem posto".
///
/// [posto] nulo distingue-se de [ordens] vazia: um operador sem posto atribuído
/// não é o mesmo que um posto sem trabalho pendente, e a mensagem que o
/// operador vê tem de ser diferente.
class FilaDeTrabalho {
  final PostoDoOperador? posto;
  final List<OrdemNaFila> ordens;

  const FilaDeTrabalho({required this.posto, required this.ordens});

  static const FilaDeTrabalho semPosto =
      FilaDeTrabalho(posto: null, ordens: []);
}

/// Ordem aberta no terminal, com o roteiro e o estado de bloqueio.
class DetalheTarefa {
  final EncomendaModel encomenda;

  /// Roteiro completo do tipo de produto, por ordem de execução.
  final List<FaseModel> fases;

  /// Incidências registadas contra esta ordem.
  final List<IncidenciaModel> incidencias;

  const DetalheTarefa({
    required this.encomenda,
    required this.fases,
    required this.incidencias,
  });

  /// A fase em curso, ou `null` se não for possível identificá-la.
  ///
  /// Devolve `null` em dois casos distintos: a ordem já percorreu o roteiro
  /// todo (`fase_atual_id` nulo), ou a fase atual não consta do roteiro
  /// carregado — o que acontece quando o roteiro do produto foi alterado depois
  /// de a ordem ter sido lançada.
  ///
  /// Nesse segundo caso é tentador devolver a primeira fase do roteiro, e era o
  /// que este ecrã fazia. Mas então o cronómetro usa o tempo estimado da fase
  /// errada, a timeline marca como "em andamento" um passo que já passou, e a
  /// confirmação de conclusão apresenta ao operador o nome de uma fase que não
  /// é aquela que ele vai fechar. Mais vale não saber e dizê-lo.
  FaseModel? get faseAtual {
    final id = encomenda.faseAtualId;
    if (id == null) return null;
    for (final f in fases) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// A ordem tem fase em curso, mas essa fase não está no roteiro carregado.
  ///
  /// Estado anómalo que o ecrã tem de comunicar: dá para ver a ordem, não dá
  /// para a trabalhar com confiança.
  bool get faseForaDoRoteiro =>
      encomenda.faseAtualId != null && faseAtual == null;

  /// A ordem não é trabalhável neste momento.
  ///
  /// Basta uma das duas condições: a coluna `em_suspenso` da ordem, ou uma
  /// incidência sem line clearance. Em regime normal andam juntas — a RPC
  /// `aplicar_wip_hold` escreve as duas —, mas uma incidência aberta sozinha
  /// também tem de travar o posto.
  bool get bloqueada =>
      encomenda.estado == EstadoOrdem.emHold ||
      incidencias.any((i) => i.estaAberta);
}

/// Uma linha do histórico do operador: a fase concluída e as paragens que a
/// interromperam.
class RegistoDeTurno {
  final HistoricoModel registo;
  final String? codigoRastreio;
  final String? nomeProduto;

  /// Paragens atribuídas a esta fase. Ver [OperadorRepository.associarParagens].
  final List<IncidenciaModel> paragens;

  const RegistoDeTurno({
    required this.registo,
    this.codigoRastreio,
    this.nomeProduto,
    this.paragens = const [],
  });

  bool get bloqueado => paragens.isNotEmpty;

  /// Motivos legíveis das paragens, sem repetições nem entradas vazias.
  List<String> get motivos {
    final vistos = <String>{};
    for (final p in paragens) {
      final m = p.rotulo;
      if (m != null) vistos.add(m);
    }
    return vistos.toList();
  }
}

/// Indicadores de ritmo de um dia de trabalho, apurados a partir dos registos.
///
/// `historico_producao` grava um único instante por fase — `data_conclusao` é
/// igual a `created_at` em todas as linhas —, pelo que não existe duração de
/// fase para somar. O que se pode medir é o **intervalo entre conclusões
/// consecutivas** do mesmo operador no mesmo dia, que aproxima o tempo de
/// ciclo sem o afirmar como tal.
class MetricasDoDia {
  /// Intervalos acima deste valor são pausas (almoço, fim de turno partido) e
  /// não ritmo de trabalho. Entram em [intervalosIgnorados], não na média.
  static const Duration limiarPausa = Duration(hours: 2);

  /// Primeira e última conclusão do dia, em hora local.
  final DateTime? primeira;
  final DateTime? ultima;

  /// Média dos intervalos entre conclusões, excluídos os que passam de
  /// [limiarPausa]. `null` quando não sobra nenhum intervalo para medir.
  final Duration? intervaloMedio;

  /// Quantos intervalos foram postos de lado por serem pausas. Vai para o PDF:
  /// uma média que esconde o que descartou não é auditável.
  final int intervalosIgnorados;

  /// Ordens distintas tocadas no dia.
  final int ordensDistintas;

  const MetricasDoDia({
    this.primeira,
    this.ultima,
    this.intervaloMedio,
    this.intervalosIgnorados = 0,
    this.ordensDistintas = 0,
  });

  factory MetricasDoDia.apurar(List<RegistoDeTurno> registos) {
    final momentos = registos
        .map((r) => r.registo.momento?.toLocal())
        .whereType<DateTime>()
        .toList()
      ..sort();

    if (momentos.isEmpty) return const MetricasDoDia();

    var soma = Duration.zero;
    var contados = 0;
    var ignorados = 0;
    for (var i = 1; i < momentos.length; i++) {
      final intervalo = momentos[i].difference(momentos[i - 1]);
      if (intervalo > limiarPausa) {
        ignorados++;
        continue;
      }
      soma += intervalo;
      contados++;
    }

    return MetricasDoDia(
      primeira: momentos.first,
      ultima: momentos.last,
      intervaloMedio:
          contados == 0 ? null : Duration(seconds: soma.inSeconds ~/ contados),
      intervalosIgnorados: ignorados,
      ordensDistintas:
          registos.map((r) => r.registo.encomendaId).whereType<int>().toSet().length,
    );
  }
}

/// Um dia de trabalho do operador, agregado para o relatório de turno.
class ResumoDeTurno {
  /// Dia do turno em hora local, à meia-noite.
  final DateTime dia;
  final int fasesConcluidas;
  final int fasesComParagem;

  const ResumoDeTurno({
    required this.dia,
    required this.fasesConcluidas,
    required this.fasesComParagem,
  });
}

/// Colunas por que o histórico do operador pode ser ordenado.
///
/// A ordenação é aplicada **no servidor**: com paginação, ordenar em memória
/// ordenaria apenas a fatia já carregada e daria uma lista que parece ordenada
/// e não está — o mesmo defeito que a pesquisa do painel de controlo teve.
///
/// Por isso mesmo esta lista não inclui "Produto" nem "Estado": o nome do
/// produto está a dois níveis de junção (`historico_producao → encomendas →
/// tipos_produto`) e o estado vem de uma relação um-para-muitos; nenhum dos
/// dois é ordenável no servidor sem uma vista na base de dados. O estado passa
/// a ser um filtro, que é exato em qualquer dos casos.
enum OrdenacaoHistorico {
  codigo,
  fase,
  data;

  /// Coluna a ordenar e, quando vive numa relação embebida, a tabela referida.
  (String coluna, String? tabela) get alvo => switch (this) {
        OrdenacaoHistorico.codigo => ('codigo_rastreio', 'encomendas'),
        OrdenacaoHistorico.fase => ('nome_fase_padrao', 'fases_padrao'),
        OrdenacaoHistorico.data => ('data_conclusao', null),
      };
}

/// Acesso aos dados do terminal do operador.
///
/// Existe separado do [EncomendasRepository] porque a audiência é outra: aqui
/// tudo é lido do ponto de vista de *um* operador e do *seu* posto. As
/// transições de estado (avançar fase, WIP hold) continuam a ser as do
/// `EncomendasRepository` — são as mesmas RPCs que o admin usa, e duplicá-las
/// aqui seria repetir o defeito que a secção 1 corrigiu.
class OperadorRepository extends BaseRepository {
  /// Projeção do histórico: a fase concluída, a ordem e o produto.
  static const String _selectHistorico = '''
        id,
        created_at,
        data_conclusao,
        encomenda_id,
        fase_concluida_id,
        utilizador_id,
        encomendas!inner (
          codigo_rastreio,
          tipos_produto:tipos_produtos_id (nome_tipo_produto)
        ),
        fases_padrao:fase_concluida_id (nome_fase_padrao, ordem)
      ''';

  // --- POSTO E FILA ---

  /// O posto atribuído ao operador com sessão iniciada, ou `null` se não tiver.
  Future<PostoDoOperador?> obterPostoAtribuido() {
    return guarda('carregar o seu posto de trabalho', () async {
      final id = utilizadorAtualId;
      if (id == null) return null;

      final dados = await client
          .from('postos_trabalho')
          .select('id, nome_posto')
          .eq('operador_id', id)
          .maybeSingle();

      if (dados == null) return null;
      return PostoDoOperador(
        id: (dados['id'] as num).toInt(),
        nome: (dados['nome_posto'] as String?) ?? 'Posto sem nome',
      );
    });
  }

  /// As ordens que estão neste momento no posto do operador.
  ///
  /// As canceladas são excluídas no servidor: não há nada a fazer com elas e
  /// não devem ocupar espaço na fila. As que estão em WIP Hold vêm na mesma,
  /// marcadas — ver [OrdemNaFila.bloqueada].
  Future<FilaDeTrabalho> obterFila() {
    return guarda('carregar a fila de trabalho', () async {
      final posto = await obterPostoAtribuido();
      if (posto == null) return FilaDeTrabalho.semPosto;

      // As fases estão ligadas ao posto pelo nome (`fases_padrao.posto_trabalho`).
      final fasesDoPosto = comoLista(
        await client
            .from('fases_padrao')
            .select('id')
            .eq('posto_trabalho', posto.nome),
      );
      final faseIds =
          fasesDoPosto.map((f) => f['id']).whereType<Object>().toList();

      if (faseIds.isEmpty) {
        return FilaDeTrabalho(posto: posto, ordens: const []);
      }

      final encomendas = comoLista(
        await client
            .from('encomendas')
            .select('''
              id,
              codigo_rastreio,
              data_entrega,
              quantidade,
              prioridade,
              tipos_produtos_id,
              fase_atual_id,
              cancelada,
              em_suspenso,
              tipos_produto:tipos_produtos_id (nome_tipo_produto),
              clientes:cliente_id (nome_cliente)
            ''')
            .eq('cancelada', false)
            .inFilter('fase_atual_id', faseIds),
      ).map(EncomendaModel.fromJson).toList();

      // Só se procuram os roteiros dos tipos de produto que aparecem mesmo na
      // fila: carregar `fases_padrao` inteira para filtrar em memória era o que
      // este ecrã fazia antes.
      final tipos =
          encomendas.map((e) => e.tipoProdutoId).whereType<int>().toSet();

      final roteiros = <int, List<int>>{};
      if (tipos.isNotEmpty) {
        final fases = comoLista(
          await client
              .from('fases_padrao')
              .select('id, ordem, tipos_produto_id')
              .inFilter('tipos_produto_id', tipos.toList())
              .order('ordem', ascending: true),
        );
        for (final f in fases) {
          final tipo = (f['tipos_produto_id'] as num?)?.toInt();
          final id = (f['id'] as num?)?.toInt();
          if (tipo == null || id == null) continue;
          roteiros.putIfAbsent(tipo, () => []).add(id);
        }
      }

      final ordens = encomendas
          .map((e) => OrdemNaFila(
                encomenda: e,
                progresso: progressoNoRoteiro(
                  roteiro: roteiros[e.tipoProdutoId] ?? const [],
                  faseAtualId: e.faseAtualId,
                ),
              ))
          .toList();

      return FilaDeTrabalho(posto: posto, ordens: ordens);
    });
  }

  /// Fração do roteiro já percorrida, pela **posição** da fase atual.
  ///
  /// Usa o índice na lista ordenada e não o valor da coluna `ordem`: o cálculo
  /// antigo — `(ordem - 1) / total` — assumia numeração contígua a começar em
  /// 1, e com uma fase removida do plano dava percentagens erradas, incluindo
  /// acima de 100%.
  ///
  /// Uma ordem sem fase atual percorreu o roteiro todo. Sem roteiro carregado,
  /// ou com uma fase que não lhe pertence, devolve 0.0 — a barra fica vazia em
  /// vez de mentir.
  static double progressoNoRoteiro({
    required List<int> roteiro,
    required int? faseAtualId,
  }) {
    if (faseAtualId == null) return 1.0;
    if (roteiro.isEmpty) return 0.0;
    final indice = roteiro.indexOf(faseAtualId);
    if (indice < 0) return 0.0;
    return (indice / roteiro.length).clamp(0.0, 1.0);
  }

  // --- DETALHE DA TAREFA ---

  /// A ordem aberta no terminal, com o roteiro do produto e as incidências.
  ///
  /// As três leituras vão em paralelo. Nenhuma tem `try/catch` próprio: se a
  /// leitura das incidências falhasse em silêncio, a ordem apareceria como
  /// desbloqueada e o operador podia retomar trabalho numa ordem em hold.
  Future<DetalheTarefa> obterDetalheTarefa(int encomendaId) {
    return guarda('carregar os detalhes da ordem', () async {
      final dados = await client
          .from('encomendas')
          .select('''
            *,
            tipos_produto:tipos_produtos_id (nome_tipo_produto),
            clientes:cliente_id (nome_cliente),
            fase_atual:fase_atual_id (id, nome_fase_padrao, ordem, posto_trabalho)
          ''')
          .eq('id', encomendaId)
          .single();

      final encomenda = EncomendaModel.fromJson(Map<String, dynamic>.from(dados));

      final resultados = await Future.wait([
        if (encomenda.tipoProdutoId != null)
          client
              .from('fases_padrao')
              .select()
              .eq('tipos_produto_id', encomenda.tipoProdutoId!)
              .order('ordem', ascending: true)
        else
          Future.value(const <Map<String, dynamic>>[]),
        client.from('incidencias').select('''
              *,
              reason_codes:reason_code_id (categoria, descricao)
            ''').eq('encomenda_id', encomendaId),
      ]);

      return DetalheTarefa(
        encomenda: encomenda,
        fases: comoLista(resultados[0]).map(FaseModel.fromJson).toList(),
        incidencias:
            comoLista(resultados[1]).map(IncidenciaModel.fromJson).toList(),
      );
    });
  }

  // --- HISTÓRICO ---

  /// Uma fatia do histórico do operador, com as paragens já associadas.
  ///
  /// Pesquisa, filtro de data e ordenação são aplicados no servidor. Aplicá-los
  /// em memória sobre uma lista paginada daria resultados que só cobrem o que
  /// já foi carregado — a pesquisa encontraria menos do que existe e a
  /// ordenação ordenaria só a fatia visível.
  ///
  /// [dia] filtra um dia de calendário **local**; é convertido para o intervalo
  /// UTC correspondente antes de ir para o servidor, porque `data_conclusao` é
  /// `timestamptz`. Sem essa conversão, o trabalho de fim de turno caía no dia
  /// seguinte.
  Future<PaginaResultado<RegistoDeTurno>> obterHistorico({
    int deslocamento = 0,
    int tamanho = tamanhoPaginaPadrao,
    String pesquisa = '',
    DateTime? dia,
    OrdenacaoHistorico ordenacao = OrdenacaoHistorico.data,
    bool ascendente = false,
    bool apenasBloqueados = false,
  }) {
    return guarda('carregar o histórico de produção', () async {
      final utilizador = utilizadorAtualId;
      if (utilizador == null) {
        return const PaginaResultado<RegistoDeTurno>(itens: [], temMais: false);
      }

      var query = client
          .from('historico_producao')
          .select(_selectHistorico)
          .eq('utilizador_id', utilizador);

      final termo = pesquisa.trim().replaceAll(RegExp(r'[,()"]'), '');
      if (termo.isNotEmpty) {
        // O `!inner` na projeção é o que permite filtrar por uma coluna da
        // encomenda sem perder o registo de histórico.
        query = query.ilike('encomendas.codigo_rastreio', '%$termo%');
      }

      if (dia != null) {
        final inicio = DateTime(dia.year, dia.month, dia.day).toUtc();
        final fim = inicio.add(const Duration(days: 1));
        query = query
            .gte('data_conclusao', inicio.toIso8601String())
            .lt('data_conclusao', fim.toIso8601String());
      }

      final (coluna, tabela) = ordenacao.alvo;
      final dados = await query
          .order(coluna, ascending: ascendente, referencedTable: tabela)
          // Desempate estável: sem ele, duas linhas com a mesma data podem
          // trocar de posição entre páginas e aparecer repetidas ou nenhuma.
          .order('id', ascending: ascendente)
          .range(deslocamento, deslocamento + tamanho);

      // A query pede `tamanho + 1` linhas: a última é apenas a sonda que diz se
      // ainda há mais alguma coisa depois desta fatia. Tem de sair antes de se
      // construir a página, ou aparece no fim desta **e** no início da seguinte.
      final todas = comoLista(dados);
      final temMais = todas.length > tamanho;
      final linhas = temMais ? todas.sublist(0, tamanho) : todas;

      final historico = linhas.map(HistoricoModel.fromJson).toList();

      // A associação precisa do histórico **completo** destas ordens, não só do
      // que calhou nesta página: a fase interrompida pode ter ficado na página
      // anterior, e nesse caso a paragem seria atribuída à primeira fase
      // visível aqui — a mesma paragem mudava de linha conforme a paginação.
      final porRegisto = await _associarParagensDasOrdens(historico);

      final registos = <RegistoDeTurno>[];
      for (var i = 0; i < historico.length; i++) {
        final h = historico[i];
        final enc = linhas[i]['encomendas'];
        final encMapa = enc is Map ? Map<String, dynamic>.from(enc) : null;
        final produto = encMapa?['tipos_produto'];

        final registo = RegistoDeTurno(
          registo: h,
          codigoRastreio: encMapa?['codigo_rastreio'] as String?,
          nomeProduto: produto is Map
              ? produto['nome_tipo_produto'] as String?
              : null,
          paragens: porRegisto[h.id] ?? const [],
        );

        if (apenasBloqueados && !registo.bloqueado) continue;
        registos.add(registo);
      }

      // [temMais] conta as linhas devolvidas pelo servidor, não as que
      // sobrevivem ao filtro de bloqueio: descontá-lo aqui faria "Carregar
      // mais" desaparecer com páginas por ler.
      return PaginaResultado(itens: registos, temMais: temMais);
    });
  }

  /// Resolve as paragens das ordens que [registos] toca, contra o histórico
  /// **completo** dessas ordens.
  ///
  /// Devolve `historico.id -> paragens`, pelo que as chaves que caiam em fases
  /// de outros operadores simplesmente não são consultadas por quem chama.
  Future<Map<int, List<IncidenciaModel>>> _associarParagensDasOrdens(
    List<HistoricoModel> registos,
  ) async {
    final encomendaIds =
        registos.map((h) => h.encomendaId).whereType<int>().toSet();

    final resultados = await Future.wait([
      _obterHistoricoDasOrdens(encomendaIds),
      _obterParagens(encomendaIds),
    ]);

    return associarParagens(
      resultados[0] as List<HistoricoModel>,
      resultados[1] as List<IncidenciaModel>,
    );
  }

  /// Histórico completo das ordens indicadas, sem filtro de utilizador.
  ///
  /// Serve só para posicionar as paragens no tempo: uma ordem passa por vários
  /// postos e vários operadores, e a fase em que a linha parou pode ter sido
  /// concluída por outra pessoa. Filtrar por operador aqui daria a associação
  /// errada nessas ordens.
  Future<List<HistoricoModel>> _obterHistoricoDasOrdens(
    Set<int> encomendaIds,
  ) async {
    if (encomendaIds.isEmpty) return const [];
    final dados = await client
        .from('historico_producao')
        .select('id, created_at, data_conclusao, encomenda_id')
        .inFilter('encomenda_id', encomendaIds.toList());
    return comoLista(dados).map(HistoricoModel.fromJson).toList();
  }

  /// Todas as paragens registadas contra um conjunto de ordens.
  Future<List<IncidenciaModel>> _obterParagens(Set<int> encomendaIds) async {
    if (encomendaIds.isEmpty) return const [];
    final dados = await client.from('incidencias').select('''
          *,
          reason_codes:reason_code_id (categoria, descricao)
        ''').inFilter('encomenda_id', encomendaIds.toList());
    return comoLista(dados).map(IncidenciaModel.fromJson).toList();
  }

  /// Liga cada paragem à fase em que aconteceu, devolvendo `historico.id -> paragens`.
  ///
  /// A RPC `aplicar_wip_hold` grava a incidência contra a **encomenda**, sem
  /// `historico_producao_id` — a coluna que o ecrã lia antes e que deixou de
  /// ser preenchida quando o bug (C) foi corrigido (o registo de histórico
  /// falso que a alimentava desapareceu).
  ///
  /// A fase interrompida é a primeira dessa encomenda a ser concluída **depois**
  /// do registo da paragem: a paragem aconteceu durante essa fase. Ligar apenas
  /// pela encomenda marcaria como bloqueadas todas as fases dessa ordem,
  /// incluindo as que decorreram sem problema nenhum.
  ///
  /// Uma paragem numa fase ainda não concluída não aparece em lado nenhum — o
  /// histórico lista fases concluídas, e essa ainda está a decorrer.
  static Map<int, List<IncidenciaModel>> associarParagens(
    List<HistoricoModel> historico,
    List<IncidenciaModel> paragens,
  ) {
    final porEncomenda = <int, List<HistoricoModel>>{};
    for (final h in historico) {
      final enc = h.encomendaId;
      if (enc == null || h.momento == null) continue;
      porEncomenda.putIfAbsent(enc, () => []).add(h);
    }
    for (final lista in porEncomenda.values) {
      lista.sort((a, b) => a.momento!.compareTo(b.momento!));
    }

    final resultado = <int, List<IncidenciaModel>>{};
    for (final p in paragens) {
      final enc = p.encomendaId;
      final inicio = p.inicio;
      if (enc == null || inicio == null) continue;

      for (final h in porEncomenda[enc] ?? const <HistoricoModel>[]) {
        if (!h.momento!.isBefore(inicio)) {
          resultado.putIfAbsent(h.id, () => []).add(p);
          break;
        }
      }
    }
    return resultado;
  }

  // --- RELATÓRIOS DE TURNO ---

  /// A atividade do operador agregada por dia de turno, mais recente primeiro.
  ///
  /// O agrupamento é feito em hora **local**: `data_conclusao` é `timestamptz`
  /// e chega em UTC, pelo que sem `toLocal()` o trabalho de fim de turno era
  /// contado no dia seguinte.
  Future<List<ResumoDeTurno>> obterTurnos() {
    return guarda('carregar os relatórios de turno', () async {
      final utilizador = utilizadorAtualId;
      if (utilizador == null) return const [];

      final dados = comoLista(
        await client
            .from('historico_producao')
            .select('id, created_at, data_conclusao, encomenda_id')
            .eq('utilizador_id', utilizador)
            .order('data_conclusao', ascending: false),
      );

      final historico = dados.map(HistoricoModel.fromJson).toList();
      final porRegisto = await _associarParagensDasOrdens(historico);

      // `LinkedHashMap` por omissão: a ordem de inserção segue a da query, pelo
      // que os turnos saem já do mais recente para o mais antigo.
      final turnos = <DateTime, ResumoDeTurno>{};
      for (final h in historico) {
        final momento = h.momento?.toLocal();
        if (momento == null) continue;
        final dia = DateTime(momento.year, momento.month, momento.day);
        final anterior = turnos[dia];
        final temParagem = (porRegisto[h.id] ?? const []).isNotEmpty;

        turnos[dia] = ResumoDeTurno(
          dia: dia,
          fasesConcluidas: (anterior?.fasesConcluidas ?? 0) + 1,
          fasesComParagem:
              (anterior?.fasesComParagem ?? 0) + (temParagem ? 1 : 0),
        );
      }

      return turnos.values.toList();
    });
  }

  /// Todos os registos de um dia, com produto, fase e paragens.
  ///
  /// Serve o PDF do relatório, que precisa da lista detalhada e não do agregado
  /// de [obterTurnos]. Sem paginação de propósito: um dia de um operador são
  /// dezenas de linhas, e um PDF truncado a meio do dia não é um relatório.
  Future<List<RegistoDeTurno>> obterRegistosDoDia(DateTime dia) {
    return guarda('carregar os registos do dia', () async {
      final utilizador = utilizadorAtualId;
      if (utilizador == null) return const <RegistoDeTurno>[];

      // Mesma conversão de fronteira que [obterHistorico]: `data_conclusao` é
      // `timestamptz` e o dia que o operador vê é o dia local.
      final inicio = DateTime(dia.year, dia.month, dia.day).toUtc();
      final fim = inicio.add(const Duration(days: 1));

      final dados = await client
          .from('historico_producao')
          .select(_selectHistorico)
          .eq('utilizador_id', utilizador)
          .gte('data_conclusao', inicio.toIso8601String())
          .lt('data_conclusao', fim.toIso8601String())
          .order('data_conclusao', ascending: true)
          .order('id', ascending: true);

      final linhas = comoLista(dados);
      final historico = linhas.map(HistoricoModel.fromJson).toList();
      final porRegisto = await _associarParagensDasOrdens(historico);

      final registos = <RegistoDeTurno>[];
      for (var i = 0; i < historico.length; i++) {
        final h = historico[i];
        final enc = linhas[i]['encomendas'];
        final encMapa = enc is Map ? Map<String, dynamic>.from(enc) : null;
        final produto = encMapa?['tipos_produto'];

        registos.add(RegistoDeTurno(
          registo: h,
          codigoRastreio: encMapa?['codigo_rastreio'] as String?,
          nomeProduto:
              produto is Map ? produto['nome_tipo_produto'] as String? : null,
          paragens: porRegisto[h.id] ?? const [],
        ));
      }

      return registos;
    });
  }

  /// Nome do operador com sessão iniciada, tal como consta em `utilizadores`.
  ///
  /// O relatório usava `email.split('@')` como nome, o que punha a parte local
  /// do endereço no cabeçalho de um documento que sai da app. A política de RLS
  /// de `utilizadores` deixa cada um ler a sua própria linha, pelo que esta
  /// leitura não precisa de função elevada.
  Future<String?> obterNomeUtilizadorAtual() {
    return guarda('obter o seu nome de utilizador', () async {
      final id = utilizadorAtualId;
      if (id == null) return null;

      final dados = await client
          .from('utilizadores')
          .select('nome_utilizador')
          .eq('utilizador_id', id)
          .maybeSingle();

      final nome = (dados?['nome_utilizador'] as String?)?.trim();
      return (nome == null || nome.isEmpty) ? null : nome;
    });
  }

  /// Email de contacto do administrador, para o botão "Contactar Administrador".
  ///
  /// Mesma função `obter_email_suporte` (SECURITY DEFINER) usada pelo portal do
  /// cliente — a política de RLS de `utilizadores` só deixa um operador ler a
  /// sua própria linha, e o administrador não tem outro contacto publicado.
  Future<String?> obterEmailSuporte() {
    return guarda('obter o contacto do administrador', () async {
      final resposta = await client.rpc('obter_email_suporte');
      return resposta as String?;
    });
  }
}
