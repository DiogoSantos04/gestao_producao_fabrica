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

  // Cancelamento (ver bug (e) em BUGS_RESOLVIDOS.md)
  final bool cancelada;
  final String? motivoCancelamento;
  final DateTime? dataCancelamento;

  final bool emSuspenso;

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
