import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/paginacao.dart';
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

  const TimelineOrdem({required this.producao, required this.incidencias});

  bool get vazia => producao.isEmpty && incidencias.isEmpty;
}

/// Acesso a ordens de produção, histórico e incidências.
///
/// As transições de estado (avançar fase, WIP hold, line clearance, cancelar)
/// passam por funções RPC transacionais na base de dados — nunca por escritas
/// soltas daqui. Ver bug (d) em BUGS_RESOLVIDOS.md.
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
          nota_tecnica,
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

      final termo = _termoPesquisa(pesquisa);
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
  PostgrestFilterBuilder<T> _aplicarFiltroEstado<T>(
    PostgrestFilterBuilder<T> query,
    FiltroEstadoOrdem filtro,
  ) {
    if (filtro == FiltroEstadoOrdem.cancelada) {
      return query.eq('cancelada', true);
    }
    final base = query.eq('cancelada', false);
    return switch (filtro) {
      FiltroEstadoOrdem.todos => base,
      FiltroEstadoOrdem.emHold => base.eq('em_suspenso', true),
      FiltroEstadoOrdem.emProducao =>
        base.eq('em_suspenso', false).not('fase_atual_id', 'is', null),
      FiltroEstadoOrdem.concluida =>
        base.eq('em_suspenso', false).isFilter('fase_atual_id', null),
      FiltroEstadoOrdem.cancelada => base, // já tratado acima
    };
  }

  /// Normaliza o termo de pesquisa, ou devolve `null` se não houver pesquisa.
  ///
  /// Vírgulas, parênteses e aspas são removidos porque são a sintaxe do `or()`
  /// do PostgREST — deixá-los passar partiria a query em vez de procurar por eles.
  static String? _termoPesquisa(String pesquisa) {
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

  /// Fases concluídas num determinado dia, para o KPI "concluídas hoje".
  Future<List<Map<String, dynamic>>> obterHistoricoDoDia(DateTime dia) {
    return guarda('carregar o histórico do dia', () async {
      final d = '${dia.year}-${dia.month.toString().padLeft(2, '0')}-${dia.day.toString().padLeft(2, '0')}';
      final dados = await client
          .from('historico_producao')
          .select('encomenda_id')
          .gte('data_conclusao', '${d}T00:00:00')
          .lte('data_conclusao', '${d}T23:59:59');
      return comoLista(dados);
    });
  }

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
      ]);
      return TimelineOrdem(
        producao: comoLista(resultados[0]).map(HistoricoModel.fromJson).toList(),
        incidencias: comoLista(resultados[1]).map(IncidenciaModel.fromJson).toList(),
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
      }).eq('id', incidenciaId);
    });
  }

  // --- TRANSIÇÕES DE ESTADO (RPCs transacionais) ---

  /// Avança a ordem para a fase seguinte.
  /// Devolve `concluida`, `proxima_fase_id` e `proxima_fase_nome`.
  Future<Map<String, dynamic>> avancarFase(int encomendaId) {
    return guarda('avançar de fase', () async {
      final res = await client.rpc(
        'avancar_fase_encomenda',
        params: {'p_encomenda_id': encomendaId},
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
