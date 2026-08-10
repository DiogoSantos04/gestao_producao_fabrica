import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/paginacao.dart';
import '../models/checklist_model.dart';
import '../models/encomenda_model.dart';
import '../models/estado_ordem.dart';
import '../models/historico_model.dart';
import '../models/incidencia_model.dart';
import '../models/reason_code_model.dart';
import 'base_repository.dart';

/// Rastreabilidade completa de uma ordem: fases concluídas e paragens.
///
/// Substitui a `List<List<dynamic>>` que era devolvida antes, onde o ecrã tinha
/// de saber que o índice 0 era produção e o 1 incidências.
class TimelineOrdem {
  final List<HistoricoModel> producao;
  final List<IncidenciaModel> incidencias;

  /// Pontos de controlo validados, indexados por `historico_producao.id`.
  ///
  /// Vive num mapa e não numa lista solta porque a unidade de leitura é a fase:
  /// a prova de conformidade só diz alguma coisa colada à fase que fechou.
  final Map<int, List<RegistoConformidade>> conformidade;

  const TimelineOrdem({
    required this.producao,
    required this.incidencias,
    this.conformidade = const {},
  });

  bool get vazia => producao.isEmpty && incidencias.isEmpty;
}

/// Um motivo de paragem agregado, para a análise de Pareto do dashboard.
///
/// A agregação é sempre feita pelo `reason_code`, nunca pela coluna de texto
/// livre `motivo`: essa é escrita pelo operador, não tem vocabulário fechado e
/// ficou vazia desde que o terminal passou a gravar motivos estruturados — ver
/// bug (D) em docs/AlteracoesNoOperador.md. Duas frases diferentes para a mesma
/// avaria contariam como dois motivos distintos e o Pareto mentiria.
class ParagemAgregada {
  /// Descrição do motivo, ou a categoria quando não há descrição.
  final String rotulo;
  final String categoria;
  final int ocorrencias;

  /// Soma da duração das paragens deste motivo. As que ainda estão abertas
  /// contam até ao instante da leitura.
  final int minutosTotais;

  const ParagemAgregada({
    required this.rotulo,
    required this.categoria,
    required this.ocorrencias,
    required this.minutosTotais,
  });

  int get minutosMedios =>
      ocorrencias == 0 ? 0 : (minutosTotais / ocorrencias).round();
}

/// Desempenho temporal de uma fase: o que o roteiro previa contra o que a
/// fábrica levou.
///
/// Fecha a lacuna entre `fases_padrao.tempo_estimado` — escrito uma vez pelo
/// admin e nunca confrontado com a realidade — e o histórico de produção.
class DesempenhoFase {
  final int faseId;
  final String nomeFase;
  final int ordemFase;
  final String nomeProduto;

  /// Fases concluídas que entraram na média.
  final int amostras;

  /// Conclusões descartadas por durarem mais do que o limite de escala.
  ///
  /// Existem porque o início de uma fase é inferido da conclusão da anterior:
  /// uma ordem parada de um dia para o outro produz uma duração que mede
  /// calendário, não execução. São mostradas em vez de escondidas.
  final int amostrasIgnoradas;

  final int minutosEstimados;
  final double minutosReais;

  /// Desvio em percentagem. Nulo quando a fase não tem tempo estimado.
  final double? desvioPercentagem;

  const DesempenhoFase({
    required this.faseId,
    required this.nomeFase,
    required this.ordemFase,
    required this.nomeProduto,
    required this.amostras,
    required this.amostrasIgnoradas,
    required this.minutosEstimados,
    required this.minutosReais,
    this.desvioPercentagem,
  });

  factory DesempenhoFase.fromJson(Map<String, dynamic> json) => DesempenhoFase(
        faseId: (json['fase_id'] as num?)?.toInt() ?? 0,
        nomeFase: (json['nome_fase'] as String?) ?? 'Fase',
        ordemFase: (json['ordem_fase'] as num?)?.toInt() ?? 0,
        nomeProduto: (json['nome_tipo_produto'] as String?) ?? 'Sem produto',
        amostras: (json['amostras'] as num?)?.toInt() ?? 0,
        amostrasIgnoradas: (json['amostras_ignoradas'] as num?)?.toInt() ?? 0,
        minutosEstimados: (json['minutos_estimados'] as num?)?.toInt() ?? 0,
        minutosReais: (json['minutos_reais_media'] as num?)?.toDouble() ?? 0,
        desvioPercentagem: (json['desvio_percentagem'] as num?)?.toDouble(),
      );

  /// A fase demorou mais do que o previsto.
  bool get acimaDoPrevisto => (desvioPercentagem ?? 0) > 0;

  /// Poucas conclusões para a média significar alguma coisa.
  ///
  /// Não esconde a linha — sinaliza-a. Uma média de duas observações é um
  /// número, não uma tendência, e o ecrã tem de o dizer.
  bool get amostraFraca => amostras < 5;
}

/// Como ordenar o Pareto das paragens.
///
/// Os dois critérios contam histórias diferentes e ambas são precisas: um
/// motivo pode ser o mais frequente e custar pouco (arranca-se depressa),
/// enquanto outro aparece três vezes por mês e come mais horas do que todos os
/// outros juntos. Escolher só um esconde metade do problema.
enum CriterioPareto {
  /// Quantas vezes a paragem aconteceu.
  ocorrencias,

  /// Quantos minutos de linha a paragem custou.
  tempoPerdido;

  String get etiqueta => switch (this) {
        CriterioPareto.ocorrencias => 'Ocorrências',
        CriterioPareto.tempoPerdido => 'Tempo perdido',
      };
}

/// Forma como uma [CondicaoEstado] compara a coluna.
enum OperadorCondicao { igual, ehNulo, naoEhNulo, menorQue }

/// Uma condição sobre uma das colunas de estado de `encomendas`.
///
/// Existe para separar *que* condições um filtro implica de *como* elas são
/// escritas no PostgREST: a precedência entre cancelada, em hold, concluída e em
/// produção é regra de negócio e passa a ser verificável sem rede.
class CondicaoEstado {
  final String coluna;
  final OperadorCondicao operador;

  /// Só é usado com [OperadorCondicao.igual] e [OperadorCondicao.menorQue].
  final Object? valor;

  const CondicaoEstado.igual(this.coluna, this.valor)
      : operador = OperadorCondicao.igual;
  const CondicaoEstado.ehNulo(this.coluna)
      : operador = OperadorCondicao.ehNulo,
        valor = null;
  const CondicaoEstado.naoEhNulo(this.coluna)
      : operador = OperadorCondicao.naoEhNulo,
        valor = null;
  const CondicaoEstado.menorQue(this.coluna, this.valor)
      : operador = OperadorCondicao.menorQue;

  @override
  bool operator ==(Object other) =>
      other is CondicaoEstado &&
      other.coluna == coluna &&
      other.operador == operador &&
      other.valor == valor;

  @override
  int get hashCode => Object.hash(coluna, operador, valor);

  @override
  String toString() => switch (operador) {
        OperadorCondicao.igual => '$coluna = $valor',
        OperadorCondicao.ehNulo => '$coluna is null',
        OperadorCondicao.naoEhNulo => '$coluna is not null',
        OperadorCondicao.menorQue => '$coluna < $valor',
      };
}

/// Acesso a ordens de produção, histórico e incidências.
///
/// As transições de estado (avançar fase, WIP hold, line clearance, cancelar)
/// passam por funções RPC transacionais na base de dados — nunca por escritas
/// soltas daqui. Ver bug (d) em docs/BUGS_RESOLVIDOS.md.
class EncomendasRepository extends BaseRepository {
  /// Projeção usada pelo painel de controlo: a ordem com cliente, produto,
  /// fase atual e incidências associadas.
  static const String _selectPainel = '''
        *,
        clientes (nome_cliente),
        tipos_produto:tipos_produtos_id (nome_tipo_produto),
        fase_atual:fase_atual_id (id, nome_fase_padrao, ordem, posto_trabalho),
        incidencias (
          id,
          motivo,
          descricao_operador,
          tipo_manutencao,
          tecnico_id,
          entidade_externa,
          diagnostico,
          nota_tecnica,
          pecas_substituidas,
          data_inicio_intervencao,
          manutencao_concluida,
          data_fim_manutencao,
          line_clearance_validado,
          estado,
          data_registo,
          utilizadores:tecnico_id (nome_utilizador),
          reason_codes (categoria, descricao)
        )
      ''';

  // --- LEITURAS ---

  /// Uma fatia das ordens do painel de controlo, mais recentes primeiro.
  ///
  /// O filtro de estado e a pesquisa são aplicados **no servidor**: de outro modo
  /// a paginação faria a pesquisa mentir, encontrando apenas o que já estivesse
  /// carregado em memória.
  ///
  /// [deslocamento] é o número de linhas já carregadas — não um índice de página —
  /// para que o recarregamento após um evento realtime possa repor exatamente o
  /// que o utilizador tinha à frente, sem o atirar de volta ao topo.
  Future<PaginaResultado<EncomendaModel>> obterParaPainel({
    int deslocamento = 0,
    int tamanho = tamanhoPaginaPadrao,
    FiltroEstadoOrdem filtro = FiltroEstadoOrdem.todos,
    String pesquisa = '',
  }) {
    return guarda('carregar as ordens de produção', () async {
      var query = _aplicarFiltroEstado(
        client.from('encomendas').select(_selectPainel),
        filtro,
      );

      final termo = termoPesquisa(pesquisa);
      if (termo != null) {
        // A pesquisa cobre o código de rastreio e o nome do cliente, mas o nome
        // vive noutra tabela. O PostgREST não permite juntar num único `or` uma
        // coluna própria e uma coluna de um recurso embebido, por isso os
        // clientes são resolvidos primeiro (tabela pequena) e entram como lista
        // de chaves estrangeiras.
        final clientes = comoLista(
          await client.from('clientes').select('id').ilike('nome_cliente', '%$termo%'),
        );
        final ids = clientes.map((c) => c['id']).whereType<Object>().toList();

        query = ids.isEmpty
            ? query.ilike('codigo_rastreio', '%$termo%')
            : query.or('codigo_rastreio.ilike.%$termo%,cliente_id.in.(${ids.join(',')})');
      }

      // Pede-se uma linha a mais do que o pedido: é a sonda que diz se ainda há
      // mais alguma coisa depois desta fatia.
      final dados = await query
          .order('id', ascending: false)
          .range(deslocamento, deslocamento + tamanho);

      return PaginaResultado.aPartirDeSondagem(
        comoLista(dados).map(EncomendaModel.fromJson).toList(),
        tamanho,
      );
    });
  }

  /// Uma única ordem, com a mesma projeção do painel.
  ///
  /// Existe para o realtime: quando um evento traz uma ordem que ainda não está
  /// carregada, ou cuja fase não se consegue resolver com os roteiros já em
  /// memória, custa uma linha ir buscá-la — contra as 50 ou mais que um
  /// recarregamento da lista traria.
  ///
  /// Devolve `null` se a linha já não existir (apagada entretanto) ou se o RLS
  /// a esconder do utilizador.
  Future<EncomendaModel?> obterUmaParaPainel(int id) {
    return guarda('carregar a ordem', () async {
      final dados =
          await client.from('encomendas').select(_selectPainel).eq('id', id).maybeSingle();
      if (dados == null) return null;
      return EncomendaModel.fromJson(Map<String, dynamic>.from(dados));
    });
  }

  /// Traduz [FiltroEstadoOrdem] para condições sobre as três colunas de estado.
  ///
  /// Segue a mesma precedência de [EstadoOrdem.derivar] — cancelada → em hold →
  /// concluída → em produção. As canceladas só aparecem no seu próprio filtro,
  /// tal como acontecia quando a filtragem era feita em memória.
  ///
  /// [hoje] só é usado por [FiltroEstadoOrdem.atrasada] e existe como parâmetro
  /// para a regra do atraso poder ser verificada sem depender do relógio.
  static List<CondicaoEstado> condicoesDoFiltro(
    FiltroEstadoOrdem filtro, {
    DateTime? hoje,
  }) {
    if (filtro == FiltroEstadoOrdem.cancelada) {
      return const [CondicaoEstado.igual('cancelada', true)];
    }
    const base = CondicaoEstado.igual('cancelada', false);
    return switch (filtro) {
      FiltroEstadoOrdem.todos => const [base],
      // Atrasada é "ainda na linha" (em produção ou em hold, logo com fase
      // atual) e com o prazo ultrapassado. `data_entrega` é uma `date`, pelo
      // que a comparação é feita com o dia de hoje sem horas: uma ordem que
      // entrega hoje ainda está dentro do prazo até ao fim do dia.
      FiltroEstadoOrdem.atrasada => [
          base,
          const CondicaoEstado.naoEhNulo('fase_atual_id'),
          CondicaoEstado.menorQue('data_entrega', _dia(hoje ?? DateTime.now())),
        ],
      FiltroEstadoOrdem.emHold => const [
          base,
          CondicaoEstado.igual('em_suspenso', true),
        ],
      FiltroEstadoOrdem.emProducao => const [
          base,
          CondicaoEstado.igual('em_suspenso', false),
          CondicaoEstado.naoEhNulo('fase_atual_id'),
        ],
      FiltroEstadoOrdem.concluida => const [
          base,
          CondicaoEstado.igual('em_suspenso', false),
          CondicaoEstado.ehNulo('fase_atual_id'),
        ],
      FiltroEstadoOrdem.cancelada => const [base], // já tratado acima
    };
  }

  /// A mesma decisão de [condicoesDoFiltro], mas sobre uma linha em memória.
  ///
  /// O painel de controlo precisa dela para decidir se uma linha que chegou por
  /// realtime pertence ao filtro que está no ecrã. A regra vive aqui, ao lado
  /// da tradução para SQL, para as duas não poderem divergir — foi a origem do
  /// bug (b) em docs/BUGS_RESOLVIDOS.md.
  static bool pertenceAoFiltro(
    FiltroEstadoOrdem filtro, {
    required bool cancelada,
    required bool emSuspenso,
    required bool temFaseAtual,
    DateTime? dataEntrega,
    DateTime? hoje,
  }) {
    // "Todas" exclui as canceladas, que só aparecem no seu próprio filtro.
    if (filtro == FiltroEstadoOrdem.todos) return !cancelada;

    if (filtro == FiltroEstadoOrdem.atrasada) {
      if (cancelada || !temFaseAtual || dataEntrega == null) return false;
      final agora = hoje ?? DateTime.now();
      final diaDeHoje = DateTime(agora.year, agora.month, agora.day);
      final prazo = DateTime(dataEntrega.year, dataEntrega.month, dataEntrega.day);
      return prazo.isBefore(diaDeHoje);
    }

    return filtro.estado ==
        EstadoOrdem.derivar(
          cancelada: cancelada,
          emSuspenso: emSuspenso,
          temFaseAtual: temFaseAtual,
        );
  }

  /// Escreve as condições de [condicoesDoFiltro] na query.
  PostgrestFilterBuilder<T> _aplicarFiltroEstado<T>(
    PostgrestFilterBuilder<T> query,
    FiltroEstadoOrdem filtro,
  ) {
    var q = query;
    for (final c in condicoesDoFiltro(filtro)) {
      q = switch (c.operador) {
        OperadorCondicao.igual => q.eq(c.coluna, c.valor as Object),
        OperadorCondicao.ehNulo => q.isFilter(c.coluna, null),
        OperadorCondicao.naoEhNulo => q.not(c.coluna, 'is', null),
        OperadorCondicao.menorQue => q.lt(c.coluna, c.valor as Object),
      };
    }
    return q;
  }

  /// Normaliza o termo de pesquisa, ou devolve `null` se não houver pesquisa.
  ///
  /// Vírgulas, parênteses e aspas são removidos porque são a sintaxe do `or()`
  /// do PostgREST — deixá-los passar partiria a query em vez de procurar por eles.
  static String? termoPesquisa(String pesquisa) {
    final termo = pesquisa.trim().replaceAll(RegExp(r'[,()"]'), '');
    return termo.isEmpty ? null : termo;
  }

  /// Ordens ativas com a fase atual, para o dashboard.
  /// Exclui canceladas, que não contam para indicadores operacionais.
  Future<List<EncomendaModel>> obterParaDashboard() {
    return guarda('carregar as encomendas do dashboard', () async {
      final dados = await client
          .from('encomendas')
          .select('*, fase_atual:fase_atual_id(nome_fase_padrao)')
          .eq('cancelada', false);
      return comoLista(dados).map(EncomendaModel.fromJson).toList();
    });
  }

  /// Ordens em curso por posto de trabalho, ligadas pela FK da fase.
  Future<List<EncomendaModel>> obterEmCursoPorPosto() {
    return guarda('carregar as ordens em curso', () async {
      final dados = await client.from('encomendas').select('''
            id,
            created_at,
            codigo_rastreio,
            em_suspenso,
            fase_atual_id,
            clientes!cliente_id(nome_cliente),
            tipos_produto!tipos_produtos_id(nome_tipo_produto),
            fases_padrao!fase_atual_id(id, nome_fase_padrao, posto_trabalho_id)
          ''').eq('cancelada', false);
      return comoLista(dados)
          .map(EncomendaModel.fromJson)
          .where((e) => e.faseAtualId != null)
          .toList();
    });
  }

  /// Ordens com relacionamentos para os relatórios e filtros de segmentação.
  Future<List<EncomendaModel>> obterParaRelatorios() {
    return guarda('carregar as encomendas para relatório', () async {
      final dados = await client
          .from('encomendas')
          .select('id, codigo_rastreio, data_entrega, fase_atual_id, cliente_id, '
              'tipos_produtos_id, clientes(nome_cliente), '
              'tipos_produto:tipos_produtos_id(nome_tipo_produto)')
          .eq('cancelada', false);
      return comoLista(dados).map(EncomendaModel.fromJson).toList();
    });
  }

  /// As [limite] ordens lançadas mais recentemente.
  Future<List<EncomendaModel>> obterUltimasLancadas({int limite = 15}) {
    return guarda('carregar as últimas encomendas', () async {
      final dados = await client
          .from('encomendas')
          .select('id, created_at, codigo_rastreio, data_entrega, quantidade, prioridade, '
              'clientes(nome_cliente), tipos_produto:tipos_produtos_id(nome_tipo_produto)')
          .eq('cancelada', false)
          .order('id', ascending: false)
          .limit(limite);
      return comoLista(dados).map(EncomendaModel.fromJson).toList();
    });
  }

  // --- HISTÓRICO E INCIDÊNCIAS ---

  /// Histórico de produção completo (usado para calcular datas de conclusão).
  ///
  /// A projeção não inclui `id`, pelo que fica em mapas: [HistoricoModel] exige
  /// a chave primária e não faz sentido inventá-la.
  Future<List<Map<String, dynamic>>> obterHistoricoCompleto() {
    return guarda('carregar o histórico de produção', () async {
      final dados = await client
          .from('historico_producao')
          .select('encomenda_id, data_conclusao, fase_concluida_id');
      return comoLista(dados);
    });
  }

  /// Data da última fase concluída de cada ordem, dentro de uma janela de dias.
  ///
  /// Serve o KPI "concluídas hoje" e a sua comparação com ontem. A versão
  /// anterior lia um dia de cada vez e devolvia só `encomenda_id`, o que
  /// bastava para "esteve em produção neste dia" mas não para "acabou neste
  /// dia": uma ordem que trabalhou ontem e fechou a última fase hoje aparecia
  /// nos dois dias e inflacionava o total de ontem — precisamente o número com
  /// que hoje passa a ser comparado.
  ///
  /// [desde] e [ate] são dias inclusivos; a janela cobre-os por inteiro.
  ///
  /// Os limites são dias **locais** convertidos para UTC antes de irem para a
  /// query, e as datas que voltam são convertidas para local. `data_conclusao`
  /// é `timestamptz` e chega em UTC: comparar o seu dia com o dia do relógio da
  /// fábrica sem converter fazia o turno da noite contar no dia errado.
  Future<Map<int, DateTime>> obterUltimasConclusoes({
    required DateTime desde,
    required DateTime ate,
  }) {
    return guarda('carregar o histórico do dia', () async {
      final inicio = DateTime(desde.year, desde.month, desde.day);
      final fim = DateTime(ate.year, ate.month, ate.day, 23, 59, 59, 999);

      final dados = await client
          .from('historico_producao')
          .select('encomenda_id, data_conclusao')
          .gte('data_conclusao', inicio.toUtc().toIso8601String())
          .lte('data_conclusao', fim.toUtc().toIso8601String());

      final ultimas = <int, DateTime>{};
      for (final linha in comoLista(dados)) {
        final id = (linha['encomenda_id'] as num?)?.toInt();
        final data = DateTime.tryParse(linha['data_conclusao']?.toString() ?? '');
        if (id == null || data == null) continue;

        final local = data.toLocal();
        final atual = ultimas[id];
        if (atual == null || local.isAfter(atual)) ultimas[id] = local;
      }
      return ultimas;
    });
  }

  /// Quantas das ordens em [idsConcluidas] fecharam a última fase em [dia].
  ///
  /// A contagem é a mesma para hoje e para ontem — uma comparação em que os
  /// dois lados fossem medidos por regras diferentes não diria nada.
  static int contarConcluidasEm(
    DateTime dia, {
    required Set<int> idsConcluidas,
    required Map<int, DateTime> ultimasConclusoes,
  }) {
    // Ambos os lados em hora local: `data_conclusao` chega em UTC e o dia que
    // interessa é o do calendário da fábrica, não o de Greenwich.
    final alvo = dia.toLocal();

    var total = 0;
    for (final id in idsConcluidas) {
      final ultima = ultimasConclusoes[id]?.toLocal();
      if (ultima == null) continue;
      if (ultima.year == alvo.year &&
          ultima.month == alvo.month &&
          ultima.day == alvo.day) {
        total++;
      }
    }
    return total;
  }

  static String _dia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Timeline de rastreabilidade de uma ordem: produção + incidências.
  Future<TimelineOrdem> obterTimeline(int encomendaId) {
    return guarda('carregar o histórico da ordem', () async {
      final resultados = await Future.wait([
        client.from('historico_producao').select('''
              *,
              fases_padrao:fase_concluida_id (nome_fase_padrao, ordem),
              utilizadores:utilizador_id (nome_utilizador)
            ''').eq('encomenda_id', encomendaId),
        client.from('incidencias').select('''
              *,
              reason_codes:reason_code_id (categoria, descricao),
              utilizadores:tecnico_id (nome_utilizador)
            ''').eq('encomenda_id', encomendaId),
        client.from('checklist_execucoes').select('''
              *,
              utilizadores:operador_id (nome_utilizador)
            ''').eq('encomenda_id', encomendaId).order('posicao'),
      ]);

      final conformidade = <int, List<RegistoConformidade>>{};
      for (final linha in comoLista(resultados[2])) {
        final registo = RegistoConformidade.fromJson(linha);
        final historico = registo.historicoProducaoId;
        if (historico == null) continue;
        conformidade.putIfAbsent(historico, () => []).add(registo);
      }

      return TimelineOrdem(
        producao: comoLista(resultados[0]).map(HistoricoModel.fromJson).toList(),
        incidencias: comoLista(resultados[1]).map(IncidenciaModel.fromJson).toList(),
        conformidade: conformidade,
      );
    });
  }

  /// Incidências por resolver, com o posto e o operador, para os alertas do dashboard.
  Future<List<Map<String, dynamic>>> obterIncidenciasAbertas() {
    return guarda('carregar as incidências ativas', () async {
      final dados = await client
          .from('incidencias')
          .select('''
            id,
            created_at,
            motivo,
            data_registo,
            historico_producao_id,
            historico_producao (
              encomenda_id,
              encomendas (codigo_rastreio),
              fases_padrao (nome_fase_padrao, posto_trabalho),
              utilizadores (nome_utilizador)
            )
          ''')
          .eq('line_clearance_validado', false)
          .order('created_at', ascending: false);
      return comoLista(dados);
    });
  }

  /// Incidências ativas por posto de trabalho.
  Future<List<IncidenciaModel>> obterIncidenciasPorPosto() {
    return guarda('carregar as incidências dos postos', () async {
      final dados = await client.from('incidencias').select('''
            id,
            posto_trabalho_id,
            encomenda_id,
            descricao_operador,
            line_clearance_validado,
            reason_codes!reason_code_id(categoria, descricao)
          ''');
      return comoLista(dados)
          .map(IncidenciaModel.fromJson)
          .where((inc) => inc.estaAberta)
          .toList();
    });
  }

  /// Os [limite] motivos de paragem mais frequentes dos últimos [dias] dias.
  ///
  /// A agregação é feita em Dart e não numa RPC com `GROUP BY` de propósito: a
  /// projeção é estreita (sete colunas) e já vem filtrada por data, pelo que o
  /// que atravessa a rede são as paragens de um mês — dezenas de linhas nesta
  /// fábrica, não milhares. Uma RPC pouparia largura de banda irrelevante e
  /// custaria uma migração e uma regra de negócio escrita em SQL, fora do
  /// alcance dos testes. Se o volume crescer uma ordem de grandeza, a troca
  /// afeta só este método.
  Future<List<ParagemAgregada>> obterParetoParagens({
    int dias = 30,
    int? limite,
    CriterioPareto criterio = CriterioPareto.ocorrencias,
  }) {
    return guarda('carregar os motivos de paragem mais frequentes', () async {
      final desde = DateTime.now().subtract(Duration(days: dias));

      final dados = await client
          .from('incidencias')
          .select('''
            reason_code_id,
            created_at,
            data_registo,
            data_fim_manutencao,
            data_line_clearance,
            reason_codes:reason_code_id (categoria, descricao)
          ''')
          .not('reason_code_id', 'is', null)
          // `created_at` é `timestamptz`: uma data sem fuso seria lida como UTC
          // e deslocaria a janela pela diferença horária da fábrica.
          .gte('created_at', desde.toUtc().toIso8601String());

      // O `id` é obrigatório em [IncidenciaModel] mas não interessa aqui; a
      // projeção não o traz para não sugerir que a linha é a incidência inteira.
      final incidencias = comoLista(dados)
          .map((linha) => IncidenciaModel.fromJson({...linha, 'id': 0}))
          .toList();

      return agregarPareto(incidencias, limite: limite, criterio: criterio);
    });
  }

  /// Estimado vs. real por fase, do maior desvio para o menor.
  ///
  /// A agregação fica no servidor: o histórico cresce com cada fase concluída
  /// de cada ordem, e o ecrã só precisa de uma linha por fase.
  Future<List<DesempenhoFase>> obterDesempenhoFases({
    DateTime? inicio,
    DateTime? fim,
    int? clienteId,
    int? tipoProdutoId,
  }) {
    return guarda('calcular o desempenho das fases', () async {
      String? dia(DateTime? d) => d == null
          ? null
          : '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}';

      final dados = await client.rpc('obter_desempenho_fases', params: {
        'p_inicio': dia(inicio),
        'p_fim': dia(fim),
        'p_cliente_id': clienteId,
        'p_tipo_produto_id': tipoProdutoId,
      });

      return comoLista(dados).map(DesempenhoFase.fromJson).toList();
    });
  }

  /// Agrupa incidências por motivo oficial e devolve as [limite] mais
  /// frequentes, da mais frequente para a menos.
  ///
  /// Incidências sem `reason_code_id` são ignoradas: não há por onde as
  /// agrupar sem cair no texto livre. Uma paragem ainda aberta conta desde o
  /// início até [agora], porque é exatamente o tempo que está a custar.
  static List<ParagemAgregada> agregarPareto(
    List<IncidenciaModel> incidencias, {
    int? limite,
    CriterioPareto criterio = CriterioPareto.ocorrencias,
    DateTime? agora,
  }) {
    final instante = agora ?? DateTime.now();
    final porMotivo = <int, ParagemAgregada>{};

    for (final inc in incidencias) {
      final motivoId = inc.reasonCodeId;
      if (motivoId == null) continue;

      final categoria = inc.categoriaReasonCode?.trim();
      final descricao = inc.descricaoReasonCode?.trim();
      final rotulo = (descricao != null && descricao.isNotEmpty)
          ? descricao
          : (categoria != null && categoria.isNotEmpty
              ? categoria
              : 'Motivo #$motivoId');

      final anterior = porMotivo[motivoId];
      porMotivo[motivoId] = ParagemAgregada(
        rotulo: anterior?.rotulo ?? rotulo,
        categoria: anterior?.categoria ??
            (categoria == null || categoria.isEmpty ? 'Geral' : categoria),
        ocorrencias: (anterior?.ocorrencias ?? 0) + 1,
        minutosTotais:
            (anterior?.minutosTotais ?? 0) + _duracaoMinutos(inc, instante),
      );
    }

    final ordenadas = ordenarPareto(porMotivo.values, criterio: criterio);

    // Sem limite devolve tudo: a curva acumulada do Pareto precisa do total
    // real, e não do total dos que couberam no ecrã.
    return limite == null ? ordenadas : ordenadas.take(limite).toList();
  }

  /// Ordena motivos de paragem pelo [criterio] escolhido.
  ///
  /// Está separado da agregação para o ecrã poder trocar de critério sem voltar
  /// à rede: os dois números já vêm calculados em cada [ParagemAgregada].
  static List<ParagemAgregada> ordenarPareto(
    Iterable<ParagemAgregada> paragens, {
    CriterioPareto criterio = CriterioPareto.ocorrencias,
  }) {
    return paragens.toList()
      ..sort((a, b) {
        // O critério escolhido manda; o outro serve de primeiro desempate.
        final principal = criterio == CriterioPareto.tempoPerdido
            ? b.minutosTotais.compareTo(a.minutosTotais)
            : b.ocorrencias.compareTo(a.ocorrencias);
        if (principal != 0) return principal;

        final secundario = criterio == CriterioPareto.tempoPerdido
            ? b.ocorrencias.compareTo(a.ocorrencias)
            : b.minutosTotais.compareTo(a.minutosTotais);
        if (secundario != 0) return secundario;

        // Desempate estável: sem ele, dois motivos empatados podiam trocar de
        // lugar entre recarregamentos e o gráfico parecia mexer sozinho.
        return a.rotulo.compareTo(b.rotulo);
      });
  }

  /// Há quanto tempo, em média, as paragens em aberto estão a bloquear a linha.
  ///
  /// Devolve `null` quando não há nenhuma paragem aberta — e não zero: "sem
  /// paragens" e "paragens que começaram agora mesmo" são situações opostas e
  /// um `0 min` no ecrã não as distinguiria.
  ///
  /// Conta desde [IncidenciaModel.inicio] até [agora], porque uma paragem
  /// aberta não tem fim: o que interessa é o tempo que já custou. Incidências
  /// sem data de início são ignoradas em vez de contarem como zero, que
  /// puxaria a média para baixo e faria a fábrica parecer melhor do que está.
  static Duration? tempoMedioParagemAberta(
    List<IncidenciaModel> incidencias, {
    DateTime? agora,
  }) {
    final instante = agora ?? DateTime.now();

    var total = 0;
    var contadas = 0;
    for (final inc in incidencias) {
      final inicio = inc.inicio;
      if (inicio == null) continue;
      // Sempre até `agora`, mesmo que a manutenção já esteja concluída: até ao
      // line clearance a linha continua bloqueada, e é o bloqueio que se mede.
      final minutos = instante.difference(inicio).inMinutes;
      total += minutos < 0 ? 0 : minutos;
      contadas++;
    }

    if (contadas == 0) return null;
    return Duration(minutes: (total / contadas).round());
  }

  /// Duração de uma paragem em minutos, nunca negativa.
  ///
  /// O fim é o momento em que a linha voltou a andar (line clearance) e não o
  /// fim da manutenção: entre os dois a ordem continua bloqueada.
  static int _duracaoMinutos(IncidenciaModel inc, DateTime agora) {
    final inicio = inc.inicio;
    if (inicio == null) return 0;
    final fim = inc.dataLineClearance ?? inc.dataFimManutencao ?? agora;
    final minutos = fim.difference(inicio).inMinutes;
    return minutos < 0 ? 0 : minutos;
  }

  /// Catálogo de motivos oficiais de paragem, sem repetições de `id`.
  ///
  /// A deduplicação é feita aqui e não em cada ecrã: o
  /// `DropdownButtonFormField` lança em runtime se receber dois itens com o
  /// mesmo valor, e tanto o painel de controlo como o terminal do operador
  /// alimentam um a partir desta lista.
  Future<List<ReasonCodeModel>> obterReasonCodes() {
    return guarda('carregar os motivos de paragem', () async {
      final dados =
          await client.from('reason_codes').select().order('categoria');

      final porId = <int, ReasonCodeModel>{};
      for (final linha in comoLista(dados)) {
        final motivo = ReasonCodeModel.fromJson(linha);
        porId[motivo.id] = motivo;
      }
      return porId.values.toList();
    });
  }

  // --- ESCRITAS ---

  /// Lança uma ordem manualmente (planeamento).
  Future<void> lancar({
    required String codigoRastreio,
    required String dataEntrega,
    required int clienteId,
    required int tipoProdutoId,
    required int faseInicialId,
    required int quantidade,
    required String prioridade,
    required String observacoes,
  }) {
    return guarda('lançar a encomenda', () async {
      await client.from('encomendas').insert({
        'codigo_rastreio': codigoRastreio,
        'data_entrega': dataEntrega,
        'cliente_id': clienteId,
        'tipos_produtos_id': tipoProdutoId,
        'fase_atual_id': faseInicialId,
        'quantidade': quantidade,
        'prioridade': prioridade,
        'observacoes': observacoes,
      });
    });
  }

  /// Altera o prazo e/ou a fase atual de uma ordem.
  Future<void> atualizar({
    required int id,
    required String dataEntrega,
    required int? faseAtualId,
  }) {
    return guarda('editar a ordem', () async {
      await client.from('encomendas').update({
        'data_entrega': dataEntrega,
        'fase_atual_id': faseAtualId,
      }).eq('id', id);
    });
  }

  /// Grava o relatório da intervenção técnica numa incidência.
  Future<void> registarIntervencaoTecnica({
    required int incidenciaId,
    required String tipoManutencao,
    required String? tecnicoId,
    required String? entidadeExterna,
    required String notaTecnica,
  }) {
    return guarda('gravar o registo técnico', () async {
      await client.from('incidencias').update({
        'tipo_manutencao': tipoManutencao,
        'tecnico_id': tecnicoId,
        'entidade_externa': entidadeExterna,
        'nota_tecnica': notaTecnica,
        'manutencao_concluida': true,
        'data_fim_manutencao': DateTime.now().toIso8601String(),
        // Mesmo estado a que a RPC do técnico chega: a origem do registo muda,
        // o ponto do ciclo em que a ordem fica não.
        'estado': 'AGUARDA_LINE_CLEARANCE',
      }).eq('id', incidenciaId);
    });
  }

  // --- TRANSIÇÕES DE ESTADO (RPCs transacionais) ---

  /// Avança a ordem para a fase seguinte.
  ///
  /// Devolve `concluida`, `proxima_fase_id`, `proxima_fase_nome`,
  /// `historico_id` e `checklist_registada`.
  ///
  /// [checklist] leva os pontos de controlo Poka-Yoke que o operador validou. A
  /// RPC grava-os em `checklist_execucoes` na **mesma transação** que escreve o
  /// histórico e avança a ordem: ou fica prova de conformidade, ou não há
  /// avanço. Gravá-los numa segunda chamada deixaria fases fechadas sem registo
  /// sempre que a rede caísse pelo meio — que é precisamente o caso em que
  /// interessa saber o que foi verificado.
  ///
  /// Uma fase com checklist chamada sem [checklist] é recusada pelo servidor,
  /// exceto para o perfil Administrador — nesse caso o desvio é gravado como
  /// não conformidade em vez de desaparecer.
  Future<Map<String, dynamic>> avancarFase(
    int encomendaId, {
    List<PontoValidado> checklist = const [],
  }) {
    return guarda('avançar de fase', () async {
      final res = await client.rpc(
        'avancar_fase_encomenda',
        params: {
          'p_encomenda_id': encomendaId,
          'p_checklist': checklist.map((p) => p.toJson()).toList(),
        },
      );
      return Map<String, dynamic>.from(res as Map);
    });
  }

  /// Suspende a ordem criando a incidência correspondente.
  Future<void> aplicarWipHold({
    required int encomendaId,
    required int reasonCodeId,
    required String descricaoOperador,
  }) {
    return guarda('aplicar o WIP Hold', () async {
      await client.rpc('aplicar_wip_hold', params: {
        'p_encomenda_id': encomendaId,
        'p_reason_code_id': reasonCodeId,
        'p_descricao_operador': descricaoOperador,
      });
    });
  }

  /// Valida o line clearance e retoma a produção.
  Future<void> aprovarLineClearance(int incidenciaId) {
    return guarda('aprovar o Line Clearance', () async {
      await client.rpc('aprovar_line_clearance', params: {
        'p_incidencia_id': incidenciaId,
      });
    });
  }

  /// Cancela a ordem preservando o histórico.
  Future<void> cancelar({required int encomendaId, required String motivo}) {
    return guarda('cancelar a ordem', () async {
      await client.rpc('cancelar_ordem', params: {
        'p_encomenda_id': encomendaId,
        'p_motivo': motivo,
      });
    });
  }

  // --- REALTIME ---

  /// Escuta alterações em `encomendas` e `incidencias`.
  ///
  /// O payload é entregue a quem escuta em vez de ser descartado: traz as
  /// colunas em bruto da linha alterada, o que chega para o painel decidir
  /// localmente se a ordem sai da lista, entra, ou apenas muda de estado — sem
  /// ir ao servidor. Não traz os recursos embebidos (cliente, produto, fase),
  /// pelo que quem precise deles ainda tem de os pedir.
  RealtimeChannel escutarProducao(
    String canal,
    void Function(PostgresChangePayload) aoAlterar,
  ) {
    return client
        .channel(canal)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encomendas',
          callback: aoAlterar,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidencias',
          callback: aoAlterar,
        )
      ..subscribe();
  }
}
