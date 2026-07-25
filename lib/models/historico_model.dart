/// Registo de conclusão de uma fase de produção (log de auditoria).
///
/// Na base de dados, `encomenda_id`, `fase_concluida_id`, `utilizador_id` e
/// `data_conclusao` são todos anuláveis; a versão anterior exigia-os todos.
class HistoricoModel {
  final int id;
  final DateTime? createdAt;
  final int? encomendaId;
  final int? faseConcluidaId;
  final String? utilizadorId;
  final DateTime? dataConclusao;

  /// Campos vindos das junções, quando pedidos.
  final String? nomeFase;
  final int? ordemFase;
  final String? nomeUtilizador;

  const HistoricoModel({
    required this.id,
    this.createdAt,
    this.encomendaId,
    this.faseConcluidaId,
    this.utilizadorId,
    this.dataConclusao,
    this.nomeFase,
    this.ordemFase,
    this.nomeUtilizador,
  });

  factory HistoricoModel.fromJson(Map<String, dynamic> json) {
    final fase = json['fases_padrao'] is Map
        ? Map<String, dynamic>.from(json['fases_padrao'] as Map)
        : null;
    final user = json['utilizadores'] is Map
        ? Map<String, dynamic>.from(json['utilizadores'] as Map)
        : null;

    return HistoricoModel(
      id: (json['id'] as num).toInt(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      encomendaId: (json['encomenda_id'] as num?)?.toInt(),
      faseConcluidaId: (json['fase_concluida_id'] as num?)?.toInt(),
      utilizadorId: json['utilizador_id'] as String?,
      dataConclusao: DateTime.tryParse(json['data_conclusao']?.toString() ?? ''),
      nomeFase: fase?['nome_fase_padrao'] as String?,
      ordemFase: (fase?['ordem'] as num?)?.toInt(),
      nomeUtilizador: user?['nome_utilizador'] as String?,
    );
  }

  /// Momento efetivo do evento: a conclusão, ou a criação do registo em falta.
  DateTime? get momento => dataConclusao ?? createdAt;
}
