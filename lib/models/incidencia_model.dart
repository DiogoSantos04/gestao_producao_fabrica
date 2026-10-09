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

  /// Quem registou a incidência. Nulo nas anteriores à coluna `registado_por`.
  final String? registadoPor;

  // Intervenção técnica
  final String? tipoManutencao;
  final String? tecnicoId;
  final String? entidadeExterna;

  /// Causa da avaria, apurada pelo técnico — não confundir com
  /// [descricaoOperador], que é o sintoma relatado por quem parou a linha.
  final String? diagnostico;

  /// Relatório das ações corretivas.
  final String? notaTecnica;
  final String? pecasSubstituidas;

  /// Momento em que o técnico pegou na incidência.
  final DateTime? dataInicioIntervencao;

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
  final String? codigoRastreio;
  final String? nomeCliente;
  final String? nomeProduto;
  final String? nomePosto;
  final String? prioridade;

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
    this.estado = 'PENDENTE',
    this.registadoPor,
    this.tipoManutencao,
    this.tecnicoId,
    this.entidadeExterna,
    this.diagnostico,
    this.notaTecnica,
    this.pecasSubstituidas,
    this.dataInicioIntervencao,
    this.manutencaoConcluida = false,
    this.dataFimManutencao,
    this.lineClearanceValidado = false,
    this.lineClearancePor,
    this.dataLineClearance,
    this.nomeTecnico,
    this.categoriaReasonCode,
    this.descricaoReasonCode,
    this.codigoRastreio,
    this.nomeCliente,
    this.nomeProduto,
    this.nomePosto,
    this.prioridade,
  });

  factory IncidenciaModel.fromJson(Map<String, dynamic> json) {
    final tecnico = _mapa(json['utilizadores']);
    final reason = _mapa(json['reason_codes']);
    final encomenda = _mapa(json['encomendas']);
    final posto = _mapa(json['postos_trabalho']);

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
      // 'EM_ABERTO' não existe na check constraint de `incidencias.estado`.
      estado: (json['estado'] as String?) ?? 'PENDENTE',
      registadoPor: json['registado_por'] as String?,
      tipoManutencao: json['tipo_manutencao'] as String?,
      tecnicoId: json['tecnico_id'] as String?,
      entidadeExterna: json['entidade_externa'] as String?,
      diagnostico: json['diagnostico'] as String?,
      notaTecnica: json['nota_tecnica'] as String?,
      pecasSubstituidas: json['pecas_substituidas'] as String?,
      dataInicioIntervencao:
          DateTime.tryParse(json['data_inicio_intervencao']?.toString() ?? ''),
      manutencaoConcluida: json['manutencao_concluida'] == true,
      dataFimManutencao: DateTime.tryParse(json['data_fim_manutencao']?.toString() ?? ''),
      lineClearanceValidado: json['line_clearance_validado'] == true,
      lineClearancePor: json['line_clearance_por'] as String?,
      dataLineClearance: DateTime.tryParse(json['data_line_clearance']?.toString() ?? ''),
      nomeTecnico: tecnico?['nome_utilizador'] as String?,
      categoriaReasonCode: reason?['categoria'] as String?,
      descricaoReasonCode: reason?['descricao'] as String?,
      codigoRastreio: encomenda?['codigo_rastreio'] as String?,
      nomeCliente: _mapa(encomenda?['clientes'])?['nome_cliente'] as String?,
      nomeProduto:
          _mapa(encomenda?['tipos_produto'])?['nome_tipo_produto'] as String?,
      nomePosto: posto?['nome_posto'] as String?,
      prioridade: encomenda?['prioridade'] as String?,
    );
  }

  /// Motivo da paragem em texto legível, ou `null` se não houver nenhum.
  ///
  /// A coluna `motivo` é texto livre e ficou vazia desde que o terminal passou
  /// a gravar motivos estruturados (bug (D)): o motivo oficial vive agora no
  /// `reason_code`. Mostra-se o que existir, do mais específico para o mais
  /// genérico, em vez de uma célula vazia.
  String? get rotulo {
    for (final candidato in [motivo, descricaoReasonCode, categoriaReasonCode]) {
      final texto = candidato?.trim();
      if (texto != null && texto.isNotEmpty) return texto;
    }
    return null;
  }

  /// A incidência ainda bloqueia a linha.
  bool get estaAberta => !lineClearanceValidado;

  /// A reparação está feita e falta apenas a validação da qualidade.
  bool get aguardaLineClearance => manutencaoConcluida && !lineClearanceValidado;

  /// Momento em que a paragem começou.
  DateTime? get inicio => dataRegisto ?? createdAt;

  /// Responsável pela intervenção: técnico interno ou entidade externa.
  String? get responsavelIntervencao => nomeTecnico ?? entidadeExterna;

  /// Um técnico já pegou na incidência e ainda não a fechou.
  bool get intervencaoEmCurso =>
      dataInicioIntervencao != null && !manutencaoConcluida;

  /// O técnico já deixou registo próprio.
  ///
  /// É o que distingue uma incidência que o administrador só tem de validar de
  /// uma que ainda tem de preencher à mão (o caso da assistência externa).
  bool get temRegistoDoTecnico =>
      (diagnostico?.trim().isNotEmpty ?? false) ||
      (notaTecnica?.trim().isNotEmpty ?? false);

  /// Tempo de reparação — a base do MTTR.
  ///
  /// Conta a partir do momento em que o técnico pegou no trabalho, e não do
  /// registo da avaria: o tempo que a incidência passou à espera é [tempoEspera],
  /// uma métrica distinta que somada a esta escondia qual dos dois é o problema.
  /// `null` enquanto a intervenção não estiver fechada.
  Duration? get duracaoIntervencao {
    final inicio = dataInicioIntervencao;
    final fim = dataFimManutencao;
    if (inicio == null || fim == null) return null;
    return fim.difference(inicio);
  }

  /// Tempo entre a paragem da linha e a chegada do técnico.
  Duration? get tempoEspera {
    final abertura = inicio;
    final atendimento = dataInicioIntervencao;
    if (abertura == null || atendimento == null) return null;
    return atendimento.difference(abertura);
  }

  static Map<String, dynamic>? _mapa(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }
}
