class IncidenciaModel {
  final int id;
  final DateTime createdAt;
  final String motivo;
  final DateTime dataRegisto;
  final int historicoProducaoId;

  IncidenciaModel({
    required this.id,
    required this.createdAt,
    required this.motivo,
    required this.dataRegisto,
    required this.historicoProducaoId,
  });

  // Converte o JSON vindo do Supabase num objeto IncidenciaModel legível pelo Flutter
  factory IncidenciaModel.fromJson(Map<String, dynamic> json) {
    return IncidenciaModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      motivo: json['motivo'] as String,
      dataRegisto: DateTime.parse(json['data_registo'] as String),
      historicoProducaoId: json['historico_producao_id'] as int,
    );
  }

  // Converte o objeto IncidenciaModel num mapa JSON para criar novos bloqueios no Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'motivo': motivo,
      'data_registo': dataRegisto.toIso8601String(),
      'historico_producao_id': historicoProducaoId,
    };
  }
}