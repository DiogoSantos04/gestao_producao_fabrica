/// Estado de um pedido submetido pelo portal B2B do cliente.
///
/// A coluna `pedidos_encomenda.estado` é texto livre com valor por omissão
/// `'Pendente'`. Os ecrãs comparavam a string à mão em vários sítios, incluindo
/// um `.or('estado.ilike.Aprovado%,estado.eq.Aprovado')` para tolerar variações.
enum EstadoPedido {
  pendente,
  aprovado,
  emProducao,
  rejeitado;

  static EstadoPedido desdeTexto(String? valor) {
    final v = (valor ?? '').trim().toLowerCase();
    if (v.startsWith('aprovado')) return EstadoPedido.aprovado;
    if (v.startsWith('em produ')) return EstadoPedido.emProducao;
    if (v.startsWith('rejeitado')) return EstadoPedido.rejeitado;
    return EstadoPedido.pendente;
  }

  /// Texto tal como é gravado na base de dados.
  String get valorBd => switch (this) {
        EstadoPedido.pendente => 'Pendente',
        EstadoPedido.aprovado => 'Aprovado',
        EstadoPedido.emProducao => 'Em Produção',
        EstadoPedido.rejeitado => 'Rejeitado',
      };

  /// Etiqueta apresentada na interface.
  String get etiqueta => valorBd;

  /// Só um pedido pendente pode ser aprovado ou rejeitado.
  bool get aguardaDecisao => this == EstadoPedido.pendente;
}

/// Pedido de encomenda submetido por um cliente através do portal.
class PedidoModel {
  final int id;
  final DateTime? createdAt;
  final int? clienteId;
  final int? tipoProdutoId;
  final int quantidade;
  final String? observacoes;
  final EstadoPedido estado;

  /// Campos vindos das junções, quando pedidos.
  final String? nomeCliente;
  final String? emailCliente;
  final String? nomeProduto;

  const PedidoModel({
    required this.id,
    this.createdAt,
    this.clienteId,
    this.tipoProdutoId,
    this.quantidade = 1,
    this.observacoes,
    this.estado = EstadoPedido.pendente,
    this.nomeCliente,
    this.emailCliente,
    this.nomeProduto,
  });

  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    final cliente = _mapa(json['clientes']);
    final produto = _mapa(json['tipos_produto']);

    return PedidoModel(
      id: (json['id'] as num).toInt(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      clienteId: (json['cliente_id'] as num?)?.toInt(),
      tipoProdutoId: (json['tipo_produto_id'] as num?)?.toInt(),
      quantidade: (json['quantidade'] as num?)?.toInt() ?? 1,
      observacoes: json['observacoes'] as String?,
      estado: EstadoPedido.desdeTexto(json['estado'] as String?),
      nomeCliente: cliente?['nome_cliente'] as String?,
      emailCliente: cliente?['email'] as String?,
      nomeProduto: produto?['nome_tipo_produto'] as String?,
    );
  }

  /// `true` quando existe texto útil no campo de observações.
  bool get temObservacoes => (observacoes ?? '').trim().isNotEmpty;

  static Map<String, dynamic>? _mapa(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }
}
