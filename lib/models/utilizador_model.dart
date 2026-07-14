class UtilizadorModel {
  final String utilizadorId;
  final String nomeUtilizador;
  final String email;
  final String perfil;

  UtilizadorModel({
    required this.utilizadorId,
    required this.nomeUtilizador,
    required this.email,
    required this.perfil,
  });

  // 1. Transforma o mapa que vem do Supabase (JSON) num objeto UtilizadorModel para usares no Flutter
  factory UtilizadorModel.fromJson(Map<String, dynamic> json) {
    return UtilizadorModel(
      utilizadorId: json['utilizador_id'] as String,
      nomeUtilizador: json['nome_utilizador'] as String,
      email: json['email'] as String,
      perfil: json['perfil'] as String,
    );
  }

  // 2. Transforma o objeto UtilizadorModel num mapa (JSON) caso precises de atualizar dados no Supabase
  Map<String, dynamic> toJson() {
    return {
      'utilizador_id': utilizadorId,
      'nome_utilizador': nomeUtilizador,
      'email': email,
      'perfil': perfil,
    };
  }
}