/// Motivo oficial de paragem de linha.
///
/// Substitui a lista de cinco strings escrita em Dart que o terminal do
/// operador usava e que era concatenada no campo de texto livre da incidência
/// (`'[Motivo] observações'`). Sem código estruturado, uma análise de Pareto
/// das paragens era impossível — ver bug (D) em AlteracoesNoOperador.md.
class ReasonCodeModel {
  final int id;
  final String categoria;
  final String descricao;

  /// Duração típica da paragem, em minutos. Nula quando não está estimada.
  final int? tempoEstimadoMinutos;

  const ReasonCodeModel({
    required this.id,
    this.categoria = 'Geral',
    this.descricao = '',
    this.tempoEstimadoMinutos,
  });

  factory ReasonCodeModel.fromJson(Map<String, dynamic> json) {
    return ReasonCodeModel(
      id: (json['id'] as num).toInt(),
      categoria: (json['categoria'] as String?)?.trim().isNotEmpty == true
          ? (json['categoria'] as String).trim()
          : 'Geral',
      descricao: (json['descricao'] as String?)?.trim() ?? '',
      tempoEstimadoMinutos: (json['tempo_estimado_minutos'] as num?)?.toInt(),
    );
  }

  /// Texto apresentado nos dropdowns: `[Categoria] descrição`.
  String get rotulo =>
      descricao.isEmpty ? '[$categoria]' : '[$categoria] $descricao';
}
