class EncomendaModel {
  final int id;
  final DateTime createdAt;
  final String codigoRastreio;
  final DateTime dataEntrega;
  final int clienteId;
  final int tiposProdutosId;
  final int faseAtualId;

  EncomendaModel({
    required this.id,
    required this.createdAt,
    required this.codigoRastreio,
    required this.dataEntrega,
    required this.clienteId,
    required this.tiposProdutosId,
    required this.faseAtualId,
  });

  // Converte o JSON vindo do Supabase num objeto EncomendaModel legível pelo Flutter
  factory EncomendaModel.fromJson(Map<String, dynamic> json) {
    return EncomendaModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      codigoRastreio: json['codigo_rastreio'] as String,
      dataEntrega: DateTime.parse(json['data_entrega'] as String),
      clienteId: json['cliente_id'] as int,
      tiposProdutosId: json['tipos_produtos_id'] as int,
      faseAtualId: json['fase_atual_id'] as int,
    );
  }

  // Converte o objeto EncomendaModel num mapa JSON para enviar ou atualizar dados no Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'codigo_rastreio': codigoRastreio,
      'data_entrega': "${dataEntrega.year.toString().padLeft(4, '0')}-${dataEntrega.month.toString().padLeft(2, '0')}-${dataEntrega.day.toString().padLeft(2, '0')}",
      'cliente_id': clienteId,
      'tipos_produtos_id': tiposProdutosId,
      'fase_atual_id': faseAtualId,
    };
  }
}