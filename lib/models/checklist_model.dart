/// Registo de conformidade Poka-Yoke de uma fase concluída.
///
/// A checklist obrigatória da fase (`fases_padrao.checklist`) era, até aqui, um
/// gate de interface: o operador marcava os pontos, o diálogo devolvia um
/// `bool` e nada ficava gravado. Um mecanismo à prova de erro sem registo não é
/// rastreável — ninguém sabe quem validou que ponto, a que horas, em que
/// unidade produzida. Estes dois modelos são as duas metades desse registo: o
/// que sai do terminal ([PontoValidado]) e o que se lê de volta
/// ([RegistoConformidade]).
library;

/// Um ponto de controlo marcado pelo operador, a caminho do servidor.
///
/// [marcadoEm] é o instante em que a caixa foi marcada, não o da conclusão da
/// fase: a diferença entre os dois é o que distingue uma verificação feita
/// ponto a ponto de uma série de cliques no fim.
class PontoValidado {
  /// Posição do item na checklist da fase, tal como o admin a ordenou.
  final int posicao;

  final String item;
  final DateTime marcadoEm;

  const PontoValidado({
    required this.posicao,
    required this.item,
    required this.marcadoEm,
  });

  /// Formato aceite pela RPC `avancar_fase_encomenda`.
  ///
  /// `conforme` vai sempre a `true`: um ponto não conforme não fecha a fase,
  /// abre uma incidência — e a RPC recusa o avanço se algum vier a `false`.
  Map<String, dynamic> toJson() => {
        'posicao': posicao,
        'item': item,
        'conforme': true,
        'marcado_em': marcadoEm.toUtc().toIso8601String(),
      };
}

/// Uma linha de `checklist_execucoes`, como é lida na rastreabilidade da ordem.
class RegistoConformidade {
  final int id;
  final int? historicoProducaoId;
  final int? encomendaId;
  final int? faseId;
  final int posicao;

  /// Texto do ponto **tal como estava** quando foi validado.
  ///
  /// É uma cópia, não uma referência: o admin pode editar a checklist da fase
  /// depois da produção, e o registo tem de continuar a dizer o que foi
  /// efetivamente verificado nesse dia.
  final String item;

  /// `false` marca um desvio — hoje, o avanço administrativo sem validação.
  final bool conforme;

  final DateTime? marcadoEm;
  final String? nomeOperador;

  const RegistoConformidade({
    required this.id,
    this.historicoProducaoId,
    this.encomendaId,
    this.faseId,
    this.posicao = 0,
    this.item = '',
    this.conforme = true,
    this.marcadoEm,
    this.nomeOperador,
  });

  factory RegistoConformidade.fromJson(Map<String, dynamic> json) {
    final utilizador = json['utilizadores'];

    return RegistoConformidade(
      id: (json['id'] as num).toInt(),
      historicoProducaoId: (json['historico_producao_id'] as num?)?.toInt(),
      encomendaId: (json['encomenda_id'] as num?)?.toInt(),
      faseId: (json['fase_id'] as num?)?.toInt(),
      posicao: (json['posicao'] as num?)?.toInt() ?? 0,
      item: (json['item'] as String?) ?? '',
      conforme: json['conforme'] as bool? ?? true,
      marcadoEm: DateTime.tryParse(json['marcado_em']?.toString() ?? ''),
      nomeOperador: utilizador is Map
          ? utilizador['nome_utilizador'] as String?
          : null,
    );
  }
}
