class HistoricoModel {
  final int id;
  final DateTime createdAt;
  final int encomendaId;
  final int faseConcluidaId;
  final String utilizadorId;
  final DateTime dataConclusao;

  HistoricoModel({
    required this.id,
    required this.createdAt,
    required this.encomendaId,
    required this.faseConcluidaId,
    required this.utilizadorId,
    required this.dataConclusao,
  });

  // Converte o JSON vindo do Supabase num objeto HistoricoModel legível pelo Flutter
  factory HistoricoModel.fromJson(Map<String, dynamic> json) {
    return HistoricoModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      encomendaId: json['encomenda_id'] as int,
      faseConcluidaId: json['fase_concluida_id'] as int,
      utilizadorId: json['utilizador_id'] as String,
      dataConclusao: DateTime.parse(json['data_conclusao'] as String),
    );
  }

  // Converte o objeto HistoricoModel num mapa JSON para registar novos logs no Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'encomenda_id': encomendaId,
      'fase_concluida_id': faseConcluidaId,
      'utilizador_id': utilizadorId,
      'data_conclusao': dataConclusao.toIso8601String(),
    };
  }
}