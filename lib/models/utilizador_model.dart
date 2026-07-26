/// Perfis de acesso à aplicação.
///
/// A base de dados guarda o perfil em texto livre e existem variantes históricas
/// para o mesmo papel ("Admin"/"Administrador", "Operador"/"Funcionario"). Este
/// enum normaliza-as num único ponto — antes cada ecrã repetia a sua própria
/// lista de comparações em minúsculas.
enum PerfilUtilizador {
  administrador,
  operador,
  cliente,
  desconhecido;

  static PerfilUtilizador desdeTexto(String? valor) {
    switch ((valor ?? '').trim().toLowerCase()) {
      case 'admin':
      case 'administrador':
        return PerfilUtilizador.administrador;
      case 'operador':
      case 'funcionario':
      case 'funcionário':
        return PerfilUtilizador.operador;
      case 'cliente':
        return PerfilUtilizador.cliente;
      default:
        return PerfilUtilizador.desconhecido;
    }
  }

  /// Etiqueta apresentada na interface.
  String get etiqueta => switch (this) {
        PerfilUtilizador.administrador => 'Administrador',
        PerfilUtilizador.operador => 'Funcionário',
        PerfilUtilizador.cliente => 'Cliente',
        PerfilUtilizador.desconhecido => 'Funcionário',
      };

  /// Valor a gravar na coluna `perfil`.
  String get valorBd => switch (this) {
        PerfilUtilizador.administrador => 'Admin',
        PerfilUtilizador.operador => 'Operador',
        PerfilUtilizador.cliente => 'Cliente',
        PerfilUtilizador.desconhecido => 'Operador',
      };
}

/// Estado de aprovação de uma conta.
enum EstadoConta {
  ativo,
  inativo,
  pendente;

  /// Converte o texto da coluna `estado_conta`.
  ///
  /// Qualquer valor não reconhecido (ou nulo) resulta em [pendente], nunca em
  /// [ativo]. O estado da conta é usado pelo `AuthService` como travão de acesso,
  /// pelo que tem de falhar fechado — o modelo anterior também assumia
  /// `'Pendente'` quando o campo vinha vazio.
  static EstadoConta desdeTexto(String? valor) {
    switch ((valor ?? '').trim().toLowerCase()) {
      case 'ativo':
        return EstadoConta.ativo;
      case 'inativo':
        return EstadoConta.inativo;
      default:
        return EstadoConta.pendente;
    }
  }

  String get valorBd => switch (this) {
        EstadoConta.ativo => 'Ativo',
        EstadoConta.inativo => 'Inativo',
        EstadoConta.pendente => 'Pendente',
      };
}

/// Conta de utilizador.
///
/// Não tem — nem pode ter — campo de palavra-passe: as credenciais vivem
/// exclusivamente no Supabase Auth (ver bug (c) em BUGS_RESOLVIDOS.md).
class UtilizadorModel {
  final String utilizadorId;
  final String nomeUtilizador;
  final String? email;
  final PerfilUtilizador perfil;
  final EstadoConta estadoConta;

  const UtilizadorModel({
    required this.utilizadorId,
    this.nomeUtilizador = '',
    this.email,
    this.perfil = PerfilUtilizador.desconhecido,
    this.estadoConta = EstadoConta.pendente,
  });

  factory UtilizadorModel.fromJson(Map<String, dynamic> json) {
    return UtilizadorModel(
      utilizadorId: json['utilizador_id'].toString(),
      nomeUtilizador: (json['nome_utilizador'] as String?) ?? '',
      email: json['email'] as String?,
      perfil: PerfilUtilizador.desdeTexto(json['perfil'] as String?),
      estadoConta: EstadoConta.desdeTexto(json['estado_conta'] as String?),
    );
  }

  UtilizadorModel copyWith({
    String? nomeUtilizador,
    PerfilUtilizador? perfil,
    EstadoConta? estadoConta,
  }) {
    return UtilizadorModel(
      utilizadorId: utilizadorId,
      nomeUtilizador: nomeUtilizador ?? this.nomeUtilizador,
      email: email,
      perfil: perfil ?? this.perfil,
      estadoConta: estadoConta ?? this.estadoConta,
    );
  }

  /// Iniciais para o avatar (ex: "Diogo Santos" → "DS").
  ///
  /// Este cálculo estava duplicado em dois ecrãs, com resultados diferentes
  /// para o mesmo nome.
  String get iniciais {
    final partes = nomeUtilizador.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes.first.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
  }
}
