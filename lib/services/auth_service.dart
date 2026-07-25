import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/utilizador_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  UtilizadorModel? _utilizadorAtual;

  UtilizadorModel? get utilizadorAtual => _utilizadorAtual;

  /// Faz o login do utilizador com Email e Password no Supabase Auth,
  /// descarrega o perfil e valida se o Administrador já ativou a conta.
  Future<UtilizadorModel?> login({
    required String email,
    required String password,
  }) async {
    try {
      final AuthResponse response = await _supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      if (response.user == null) {
        throw Exception('Utilizador não encontrado no sistema de autenticação.');
      }

      // Procura o perfil na tabela através do UUID do utilizador autenticado
      final perfil = await obterUtilizadorPorId(response.user!.id);

      // 🛡️ TRAVÃO DE SEGURANÇA: Bloqueia o acesso se o estado não for 'Ativo'
      if (perfil.estadoConta != EstadoConta.ativo) {
        await logout(); // Força o logout imediato no Supabase Auth para não deixar a sessão aberta
        throw Exception('A sua conta está pendente de aprovação ou foi inativada pelo Administrador.');
      }

      _utilizadorAtual = perfil;
      return _utilizadorAtual;
    } catch (e) {
      rethrow;
    }
  }

  /// Vai buscar os dados completos de um utilizador/operador à tabela 
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
        final perfil = await obterUtilizadorPorId(session.user!.id);
        
        // 🛡️ Valida se a conta ainda continua ativa na retoma da sessão
        if (perfil.estadoConta != EstadoConta.ativo) {
          await logout();
          return null;
        }

        _utilizadorAtual = perfil;
        return _utilizadorAtual;
      } catch (_) {
        _utilizadorAtual = null;
        return null;
      }
    }
    return null;
  }

  // =========================================================================
  // NOVAS FUNÇÕES: GESTÃO DE UTILIZADORES (LADO DO ADMINISTRADOR)
  // =========================================================================

  /// Procura todos os utilizadores registados na base de dados para exibir 
  /// na tabela de controlo do Administrador.
  Future<List<UtilizadorModel>> obterTodosUtilizadores() async {
    try {
      final List<dynamic> data = await _supabase
          .from('utilizadores')
          .select()
          .order('nome_utilizador', ascending: true);

      return data.map((json) => UtilizadorModel.fromJson(json)).toList();
    } catch (e) {
      print('❌ Erro ao obter lista global de utilizadores: $e');
      throw Exception('Falha ao carregar a lista de utilizadores.');
    }
  }

  /// Permite ao Administrador aprovar, ativar ou inativar contas diretamente 
  /// a partir da interface da aplicação.
  Future<void> atualizarEstadoUtilizador({
    required String utilizadorId,
    required String novoEstado, // Ex: 'Ativo', 'Inativo', 'Pendente'
  }) async {
    try {
      await _supabase
          .from('utilizadores')
          .update({'estado_conta': novoEstado}) // Atualiza o estado na coluna correspondente
          .eq('utilizador_id', utilizadorId);

      print('⚙️ [Admin Auth] Utilizador $utilizadorId atualizado para: $novoEstado');
    } catch (e) {
      print('❌ Erro ao atualizar estado do utilizador ($utilizadorId): $e');
      throw Exception('Não foi possível alterar o estado de acesso do utilizador.');
    }
  }
}