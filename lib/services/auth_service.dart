import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/utilizador_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  UtilizadorModel? _utilizadorAtual;

  UtilizadorModel? get utilizadorAtual => _utilizadorAtual;

  /// Faz o login do utilizador com Email e Password no Supabase Auth
  /// e descarrega os dados do perfil interno da tabela 'utilizadores'.
  Future<UtilizadorModel?> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Utilizador não encontrado no sistema de autenticação.');
      }

      // Procura o perfil na tabela através do UUID do utilizador autenticado
      _utilizadorAtual = await obterUtilizadorPorId(response.user!.id);
      return _utilizadorAtual;
    } catch (e) {
      rethrow;
    }
  }

  /// [NOVO] Vai buscar os dados completos de um utilizador/operador à tabela 
  /// 'utilizadores' usando o seu UUID único.
  Future<UtilizadorModel> obterUtilizadorPorId(String uid) async {
    try {
      final data = await _supabase
          .from('utilizadores')
          .select()
          .eq('utilizador_id', uid)
          .single();

      return UtilizadorModel.fromJson(data);
    } catch (e) {
      print('❌ Erro ao obter dados do utilizador ($uid): $e');
      throw Exception('Erro ao carregar dados do perfil do utilizador.');
    }
  }

  /// Faz o logout seguro da conta atual e limpa os dados em memória.
  Future<void> logout() async {
    await _supabase.auth.signOut();
    _utilizadorAtual = null;
  }

  /// Verifica se já existe uma sessão ativa (caso o utilizador feche e abra a app)
  Future<UtilizadorModel?> verificarSessaoAtiva() async {
    final Session? session = _supabase.auth.currentSession;
    if (session != null && session.user != null) {
      try {
        _utilizadorAtual = await obterUtilizadorPorId(session.user!.id);
        return _utilizadorAtual;
      } catch (_) {
        _utilizadorAtual = null;
        return null;
      }
    }
    return null;
  }
}