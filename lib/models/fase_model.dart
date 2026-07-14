class FaseModel {
  final int id;
  final DateTime createdAt;
  final String nomeFasePadrao;
  final int ordem;
  final int tiposProdutoId;

  FaseModel({
    required this.id,
    required this.createdAt,
    required this.nomeFasePadrao,
    required this.ordem,
    required this.tiposProdutoId,
  });

  // Converte o JSON vindo do Supabase num objeto FaseModel legível pelo Flutter
  factory FaseModel.fromJson(Map<String, dynamic> json) {
    return FaseModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      nomeFasePadrao: json['nome_fase_padrao'] as String,
      ordem: json['ordem'] as int,
      tiposProdutoId: json['tipos_produto_id'] as int,
    );
  }

  // Converte o objeto FaseModel num mapa JSON para enviar ou atualizar dados no Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'nome_fase_padrao': nomeFasePadrao,
      'ordem': ordem,
      'tipos_produto_id': tiposProdutoId,
    };
  }
}