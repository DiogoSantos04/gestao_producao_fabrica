/// Paragem ou bloqueio na linha de produção.
///
/// Cobre o ciclo completo: registo (WIP Hold) → intervenção técnica →
/// line clearance. A versão anterior só tinha 5 campos, todos obrigatórios,
/// e ignorava todo o fluxo de manutenção.
class IncidenciaModel {
  final int id;
  final DateTime? createdAt;
  final String? motivo;
  final DateTime? dataRegisto;
  final int? encomendaId;
  final int? historicoProducaoId;
  final int? postoTrabalhoId;
  final int? reasonCodeId;
  final String? descricaoOperador;
  final String estado;

  // Intervenção técnica
  final String? tipoManutencao;
  final String? tecnicoId;
  final String? entidadeExterna;
  final String? notaTecnica;
  final bool manutencaoConcluida;
  final DateTime? dataFimManutencao;

  // Line clearance
  final bool lineClearanceValidado;
  final String? lineClearancePor;
  final DateTime? dataLineClearance;

  /// Campos vindos das junções, quando pedidos.
  final String? nomeTecnico;
  final String? categoriaReasonCode;
  final String? descricaoReasonCode;

  const IncidenciaModel({
    required this.id,
    this.createdAt,
    this.motivo,
    this.dataRegisto,
    this.encomendaId,
    this.historicoProducaoId,
    this.postoTrabalhoId,
    this.reasonCodeId,
    this.descricaoOperador,
    this.estado = 'EM_ABERTO',
    this.tipoManutencao,
    this.tecnicoId,
    this.entidadeExterna,
    this.notaTecnica,
    this.manutencaoConcluida = false,
    this.dataFimManutencao,
    this.lineClearanceValidado = false,
    this.lineClearancePor,
    this.dataLineClearance,
    this.nomeTecnico,
    this.categoriaReasonCode,
    this.descricaoReasonCode,
  });

  factory IncidenciaModel.fromJson(Map<String, dynamic> json) {
    final tecnico = _mapa(json['utilizadores']);
    final reason = _mapa(json['reason_codes']);

    return IncidenciaModel(
      id: (json['id'] as num).toInt(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      motivo: json['motivo'] as String?,
      dataRegisto: DateTime.tryParse(json['data_registo']?.toString() ?? ''),
      encomendaId: (json['encomenda_id'] as num?)?.toInt(),
      historicoProducaoId: (json['historico_producao_id'] as num?)?.toInt(),
      postoTrabalhoId: (json['posto_trabalho_id'] as num?)?.toInt(),
      reasonCodeId: (json['reason_code_id'] as num?)?.toInt(),
      descricaoOperador: json['descricao_operador'] as String?,
      estado: (json['estado'] as String?) ?? 'EM_ABERTO',
      tipoManutencao: json['tipo_manutencao'] as String?,
      tecnicoId: json['tecnico_id'] as String?,
      entidadeExterna: json['entidade_externa'] as String?,
      notaTecnica: json['nota_tecnica'] as String?,
      manutencaoConcluida: json['manutencao_concluida'] == true,
      dataFimManutencao: DateTime.tryParse(json['data_fim_manutencao']?.toString() ?? ''),
      lineClearanceValidado: json['line_clearance_validado'] == true,
      lineClearancePor: json['line_clearance_por'] as String?,
      dataLineClearance: DateTime.tryParse(json['data_line_clearance']?.toString() ?? ''),
      nomeTecnico: tecnico?['nome_utilizador'] as String?,
      categoriaReasonCode: reason?['categoria'] as String?,
      descricaoReasonCode: reason?['descricao'] as String?,
    );
  }

  /// A incidência ainda bloqueia a linha.
  bool get estaAberta => !lineClearanceValidado;

  /// A reparação está feita e falta apenas a validação da qualidade.
  bool get aguardaLineClearance => manutencaoConcluida && !lineClearanceValidado;

  /// Momento em que a paragem começou.
  DateTime? get inicio => dataRegisto ?? createdAt;

  /// Responsável pela intervenção: técnico interno ou entidade externa.
  String? get responsavelIntervencao => nomeTecnico ?? entidadeExterna;

  static Map<String, dynamic>? _mapa(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }
}
