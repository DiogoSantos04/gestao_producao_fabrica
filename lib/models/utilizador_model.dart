class UtilizadorModel {
  final String utilizadorId;
  final String nomeUtilizador;
  final String email;
  final String perfil;
  final String estadoConta; // 🛡️ ADICIONADO: Campo para controlar se a conta está ativa ou pendente

  UtilizadorModel({
    required this.utilizadorId,
    required this.nomeUtilizador,
    required this.email,
    required this.perfil,
    required this.estadoConta, // 🛡️ ADICIONADO
  });

  // 1. Transforma o mapa que vem do Supabase (JSON) num objeto UtilizadorModel para usares no Flutter
  factory UtilizadorModel.fromJson(Map<String, dynamic> json) {
    return UtilizadorModel(
      utilizadorId: json['utilizador_id'] as String,
      nomeUtilizador: json['nome_utilizador'] as String,
      email: json['email'] as String,
      perfil: json['perfil'] as String,
      // 🛡️ ADICIONADO: Se a coluna na base de dados se chamar 'estado_conta'
      // Caso no teu banco seja apenas 'estado', podes mudar a string abaixo para json['estado']
      estadoConta: (json['estado_conta'] ?? 'Pendente') as String, 
    );
  }

  // 2. Transforma o objeto UtilizadorModel num mapa (JSON) caso precises de atualizar dados no Supabase
  Map<String, dynamic> toJson() {
    return {
      'utilizador_id': utilizadorId,
      'nome_utilizador': nomeUtilizador,
      'email': email,
      'perfil': perfil,
      'estado_conta': estadoConta, // 🛡️ ADICIONADO
    };
  }
}