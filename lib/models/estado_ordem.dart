/// Estado de uma ordem de produção.
///
/// Esta é a **definição única** do estado de uma ordem. Antes do refactor, cada
/// ecrã derivava o estado à sua maneira a partir de três colunas soltas
/// (`cancelada`, `em_suspenso`, `fase_atual_id`), e as regras divergiam:
/// os relatórios chegaram a considerar "concluída" uma ordem que estava apenas
/// *na* última fase, o que inflacionava os KPIs (ver bug (b) em docs/BUGS_RESOLVIDOS.md).
///
/// A ordem de avaliação importa: uma ordem cancelada é cancelada mesmo que
/// tenha ficado suspensa, e uma ordem suspensa continua a ter fase atual.
enum EstadoOrdem {
  emProducao,
  emHold,
  concluida,
  cancelada;

  /// Deriva o estado a partir das colunas da tabela `encomendas`.
  ///
  /// - `cancelada = true` → [cancelada] (prevalece sobre tudo)
  /// - `em_suspenso = true` → [emHold]
  /// - `fase_atual_id = null` → [concluida] (percorreu todo o roteiro)
  /// - caso contrário → [emProducao]
  static EstadoOrdem derivar({
    required bool cancelada,
    required bool emSuspenso,
    required bool temFaseAtual,
  }) {
    if (cancelada) return EstadoOrdem.cancelada;
    if (emSuspenso) return EstadoOrdem.emHold;
    if (!temFaseAtual) return EstadoOrdem.concluida;
    return EstadoOrdem.emProducao;
  }

  /// Texto apresentado nos badges da interface.
  String get etiqueta => switch (this) {
        EstadoOrdem.emProducao => 'EM PRODUÇÃO',
        EstadoOrdem.emHold => 'ON HOLD',
        EstadoOrdem.concluida => 'CONCLUÍDA',
        EstadoOrdem.cancelada => 'CANCELADA',
      };

  /// A ordem já saiu da linha, por conclusão ou cancelamento.
  bool get eFinal => this == EstadoOrdem.concluida || this == EstadoOrdem.cancelada;

  /// A ordem conta para indicadores operacionais (ativas, atrasadas, ocupação).
  bool get contaParaIndicadores => this != EstadoOrdem.cancelada;

  /// A ordem está a ocupar um posto de trabalho.
  bool get estaNaLinha => this == EstadoOrdem.emProducao || this == EstadoOrdem.emHold;
}

/// Filtro de estado escolhido pelo utilizador no painel de controlo.
///
/// Existe separado de [EstadoOrdem] porque inclui o valor "todos", que não é um
/// estado de nenhuma ordem, e porque a tradução para condições SQL vive num só
/// sítio — o `EncomendasRepository`. Enquanto a filtragem era feita em memória
/// bastava comparar com [EstadoOrdem]; agora que desce para o servidor, o risco
/// é a regra ficar escrita duas vezes e divergir, que foi exatamente a origem do
/// bug (b) em docs/BUGS_RESOLVIDOS.md.
enum FiltroEstadoOrdem {
  todos,
  emProducao,
  emHold,

  /// Ordens ainda na linha cujo prazo de entrega já passou.
  ///
  /// É o único filtro que não corresponde a um [EstadoOrdem]: o atraso não é um
  /// estado guardado, é o cruzamento de "ainda não saiu da linha" com
  /// `data_entrega`. Uma ordem atrasada está ao mesmo tempo em produção ou em
  /// hold — por isso [estado] é `null` aqui.
  atrasada,

  concluida,
  cancelada;

  /// O estado que este filtro seleciona, ou `null` quando não seleciona um
  /// estado único ([todos] e [atrasada]).
  EstadoOrdem? get estado => switch (this) {
        FiltroEstadoOrdem.todos => null,
        FiltroEstadoOrdem.atrasada => null,
        FiltroEstadoOrdem.emProducao => EstadoOrdem.emProducao,
        FiltroEstadoOrdem.emHold => EstadoOrdem.emHold,
        FiltroEstadoOrdem.concluida => EstadoOrdem.concluida,
        FiltroEstadoOrdem.cancelada => EstadoOrdem.cancelada,
      };

  /// Texto do cabeçalho quando o filtro chega já aplicado de outro ecrã.
  String get etiqueta => switch (this) {
        FiltroEstadoOrdem.todos => 'Todas',
        FiltroEstadoOrdem.emProducao => 'Em Produção',
        FiltroEstadoOrdem.emHold => 'ON HOLD',
        FiltroEstadoOrdem.atrasada => 'Atrasadas',
        FiltroEstadoOrdem.concluida => 'Concluídas',
        FiltroEstadoOrdem.cancelada => 'Canceladas',
      };
}
