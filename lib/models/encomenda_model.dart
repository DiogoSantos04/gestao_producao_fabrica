import 'estado_ordem.dart';

/// Ordem de produção.
///
/// Todos os campos anuláveis na base de dados são anuláveis aqui. A versão
/// anterior deste modelo declarava tudo como obrigatório e usava `as int` /
/// `as String` diretos, pelo que rebentava em qualquer ordem concluída
/// (`fase_atual_id` é nulo) — razão pela qual nunca chegou a ser usado.
class EncomendaModel {
  final int id;
  final DateTime? createdAt;
  final String? codigoRastreio;
  final DateTime? dataEntrega;
  final int? clienteId;
  final int? tipoProdutoId;
  final int? faseAtualId;
  final int quantidade;
  final String prioridade;
  final String? observacoes;

  // Cancelamento (ver bug (e) em docs/BUGS_RESOLVIDOS.md)
  final bool cancelada;
  final String? motivoCancelamento;
  final DateTime? dataCancelamento;

  final bool emSuspenso;

  /// Momento em que a ordem entrou na fase atual, escrito por
  /// `avancar_fase_encomenda` na mesma transação da transição.
  ///
  /// É a origem do cronómetro do terminal do operador. Fica nulo numa ordem
  /// concluída (não há fase a decorrer) e nas ordens anteriores à migração
  /// `add_data_inicio_fase_encomendas` cujo backfill não encontrou referência.
  final DateTime? dataInicioFase;

  /// Segundos que a fase atual esteve parada em WIP Hold.
  ///
  /// Acumulado pelo servidor a cada line clearance e reposto a zero quando a
  /// ordem muda de fase. Existe para que o tempo de avaria não conte como tempo
  /// de produção sem ter de falsificar [dataInicioFase], que é o momento real em
  /// que a fase começou e o que o histórico usa.
  final int segundosParadosFase;

  /// Campos vindos das junções. Ficam nulos quando a query não os pediu.
  final String? nomeCliente;
  final String? nomeProduto;
  final String? nomeFaseAtual;
  final int? ordemFaseAtual;
  final String? postoFaseAtual;
  final int? postoFaseAtualId;

  /// Incidências associadas, quando a query as trouxe.
  final List<Map<String, dynamic>> incidencias;

  const EncomendaModel({
    required this.id,
    this.createdAt,
    this.codigoRastreio,
    this.dataEntrega,
    this.clienteId,
    this.tipoProdutoId,
    this.faseAtualId,
    this.quantidade = 1,
    this.prioridade = 'Normal',
    this.observacoes,
    this.cancelada = false,
    this.motivoCancelamento,
    this.dataCancelamento,
    this.emSuspenso = false,
    this.dataInicioFase,
    this.segundosParadosFase = 0,
    this.nomeCliente,
    this.nomeProduto,
    this.nomeFaseAtual,
    this.ordemFaseAtual,
    this.postoFaseAtual,
    this.postoFaseAtualId,
    this.incidencias = const [],
  });

  factory EncomendaModel.fromJson(Map<String, dynamic> json) {
    // A fase atual chega com nomes de alias diferentes conforme a query
    // (`fase_atual` no painel, `fases_padrao` no ecrã de postos).
    final fase = _comoMapa(json['fase_atual']) ?? _comoMapa(json['fases_padrao']);
    final cliente = _comoMapa(json['clientes']);
    final produto = _comoMapa(json['tipos_produto']);

    return EncomendaModel(
      id: _inteiro(json['id'])!,
      createdAt: _data(json['created_at']),
      codigoRastreio: json['codigo_rastreio'] as String?,
      dataEntrega: _data(json['data_entrega']),
      clienteId: _inteiro(json['cliente_id']),
      tipoProdutoId: _inteiro(json['tipos_produtos_id']),
      faseAtualId: _inteiro(json['fase_atual_id']),
      quantidade: _inteiro(json['quantidade']) ?? 1,
      prioridade: (json['prioridade'] as String?) ?? 'Normal',
      observacoes: json['observacoes'] as String?,
      cancelada: json['cancelada'] == true,
      motivoCancelamento: json['motivo_cancelamento'] as String?,
      dataCancelamento: _data(json['data_cancelamento']),
      emSuspenso: json['em_suspenso'] == true,
      dataInicioFase: _data(json['data_inicio_fase']),
      segundosParadosFase: _inteiro(json['segundos_parados_fase']) ?? 0,
      nomeCliente: cliente?['nome_cliente'] as String?,
      nomeProduto: produto?['nome_tipo_produto'] as String?,
      nomeFaseAtual: fase?['nome_fase_padrao'] as String?,
      ordemFaseAtual: _inteiro(fase?['ordem']),
      postoFaseAtual: fase?['posto_trabalho'] as String?,
      postoFaseAtualId: _inteiro(fase?['posto_trabalho_id']),
      incidencias: _comoListaDeMapas(json['incidencias']),
    );
  }

  /// Estado derivado pela regra única de [EstadoOrdem].
  EstadoOrdem get estado => EstadoOrdem.derivar(
        cancelada: cancelada,
        emSuspenso: emSuspenso,
        temFaseAtual: faseAtualId != null,
      );

  /// Data de entrega no formato `aaaa-mm-dd` que o Postgres espera.
  String? get dataEntregaIso {
    final d = dataEntrega;
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Fração do roteiro já percorrida, entre 0.0 e 1.0.
  ///
  /// [totalFases] é o número de fases do roteiro do tipo de produto desta ordem
  /// (0 quando o roteiro não está carregado ou não existe).
  ///
  /// Vivia como método privado do `painel_controlo_screen`, onde ia buscar as
  /// fases a um campo de estado — o que a tornava impossível de testar sem
  /// construir o ecrã. Recebe agora o total como parâmetro e é pura.
  ///
  /// Uma ordem sem fase atual percorreu o roteiro todo: 1.0. Sem informação
  /// suficiente para calcular (produto desconhecido, ordem da fase desconhecida,
  /// roteiro por carregar) devolve 0.0 — a barra fica vazia em vez de mentir.
  double progressoNoRoteiro(int totalFases) {
    if (faseAtualId == null) return 1.0;
    if (tipoProdutoId == null || ordemFaseAtual == null) return 0.0;
    if (totalFases <= 0) return 0.0;

    return ((ordemFaseAtual! - 1) / totalFases).clamp(0.0, 1.0);
  }

  /// A ordem foi concluída dentro do prazo prometido.
  ///
  /// Compara **ao dia**: entregar no próprio dia do prazo conta como estando no
  /// prazo. Sem prazo prometido devolve `false` — a taxa de entrega no prazo só
  /// pode contar ordens que tinham prazo a cumprir.
  static bool cumpriuPrazo(DateTime? prometida, DateTime dataConclusao) {
    if (prometida == null) return false;

    final pDia = DateTime(prometida.year, prometida.month, prometida.day);
    final cDia = DateTime(dataConclusao.year, dataConclusao.month, dataConclusao.day);
    return !cDia.isAfter(pDia);
  }

  /// Incidência que ainda não recebeu line clearance, se existir.
  Map<String, dynamic>? get incidenciaAtiva {
    for (final i in incidencias) {
      if (i['line_clearance_validado'] != true) return i;
    }
    return null;
  }

  // --- Conversões tolerantes ---
  // O Supabase devolve inteiros como int, mas em web pode chegar num ou String.

  static int? _inteiro(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static DateTime? _data(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static Map<String, dynamic>? _comoMapa(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    // Alguns joins devolvem lista de um elemento em vez de objeto.
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  static List<Map<String, dynamic>> _comoListaDeMapas(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}
