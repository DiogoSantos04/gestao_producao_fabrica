/// Fase do roteiro de fabrico de um tipo de produto.
///
/// Campos anuláveis na base de dados são anuláveis aqui — a versão anterior
/// exigia `nome_fase_padrao`, `ordem` e `tipos_produto_id` obrigatórios.
class FaseModel {
  final int id;
  final DateTime? createdAt;
  final String nomeFasePadrao;
  final int ordem;
  final int? tipoProdutoId;
  final String? descricao;
  final int tempoEstimado;

  /// Nome do posto em texto (coluna legada, mantida sincronizada por trigger).
  final String? postoTrabalho;

  /// Ligação real ao posto de trabalho (ver bug (a) em BUGS_RESOLVIDOS.md).
  final int? postoTrabalhoId;

  final List<String> checklist;

  const FaseModel({
    required this.id,
    this.createdAt,
    this.nomeFasePadrao = '',
    this.ordem = 0,
    this.tipoProdutoId,
    this.descricao,
    this.tempoEstimado = 0,
    this.postoTrabalho,
    this.postoTrabalhoId,
    this.checklist = const [],
  });

  factory FaseModel.fromJson(Map<String, dynamic> json) {
    return FaseModel(
      id: (json['id'] as num).toInt(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      nomeFasePadrao: (json['nome_fase_padrao'] as String?) ?? '',
      ordem: (json['ordem'] as num?)?.toInt() ?? 0,
      tipoProdutoId: (json['tipos_produto_id'] as num?)?.toInt(),
      descricao: json['descricao'] as String?,
      tempoEstimado: (json['tempo_estimado'] as num?)?.toInt() ?? 0,
      postoTrabalho: json['posto_trabalho'] as String?,
      postoTrabalhoId: (json['posto_trabalho_id'] as num?)?.toInt(),
      checklist: _checklist(json['checklist']),
    );
  }

  static List<String> _checklist(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }
}
