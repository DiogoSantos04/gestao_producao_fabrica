import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/sessao_local.dart';
import '../models/utilizador_model.dart';
import '../repositories/base_repository.dart';

/// Autenticação e perfil do utilizador com sessão iniciada.
///
/// Estende [BaseRepository] pela mesma razão que os restantes acessos a dados:
/// todas as falhas saem daqui como [RepositoryException] com texto de negócio,
/// em vez de `Exception` cru que os ecrãs tinham de limpar à mão.
///
/// A gestão de contas do lado do administrador (listar, aprovar, inativar) vive
/// em `UtilizadoresRepository` — este serviço trata apenas da sessão própria.
class AuthService extends BaseRepository {
  UtilizadorModel? _utilizadorAtual;

  UtilizadorModel? get utilizadorAtual => _utilizadorAtual;


  /// Inicia sessão, carrega o perfil e valida se a conta está aprovada.
  ///
  /// Devolve sempre um utilizador: qualquer caminho que não chegue a um perfil
  /// válido lança. Qualquer falha depois do `signInWithPassword` fecha a sessão
  /// que ele abriu — caso contrário ficaria uma sessão ativa e persistida
  /// enquanto a interface diz que o login falhou, e a app entraria autenticada
  /// no arranque seguinte.
  Future<UtilizadorModel> login({
    required String email,
    required String password,
  }) {
    return guarda('iniciar sessão', () async {
      final AuthResponse resposta = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = resposta.user;
      if (user == null) {
        throw const RepositoryException(
          'Não foi possível iniciar sessão. Verifique os dados introduzidos.',
        );
      }

      final UtilizadorModel perfil;
      try {
        perfil = await obterUtilizadorPorId(user.id);
      } catch (_) {
        await logout();
        rethrow;
      }

      // Travão de acesso: só contas aprovadas entram.
      if (perfil.estadoConta != EstadoConta.ativo) {
        await logout();
        throw const RepositoryException(
          'A sua conta está pendente de aprovação ou foi inativada pelo Administrador.',
        );
      }

      _utilizadorAtual = perfil;
      return perfil;
    });
  }

  /// Carrega o perfil de `utilizadores` a partir do UUID do Auth.
  ///
  /// Usa `maybeSingle` de propósito: uma credencial sem linha de perfil é uma
  /// situação concreta e recuperável (o administrador tem de criar o registo) e
  /// tem de ser distinguível de uma falha de rede. Com `single`, as duas davam a
  /// mesma mensagem genérica e ninguém conseguia diagnosticar a diferença.
  Future<UtilizadorModel> obterUtilizadorPorId(String uid) {
    return guarda('carregar o perfil do utilizador', () async {
      final dados = await client
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil, estado_conta')
          .eq('utilizador_id', uid)
          .maybeSingle();

      if (dados == null) {
        throw const RepositoryException(
          'A sua credencial existe, mas não tem perfil associado. '
          'Contacte o Administrador.',
        );
      }

      return UtilizadorModel.fromJson(Map<String, dynamic>.from(dados));
    });
  }

  /// Termina a sessão e limpa o perfil em memória.
  ///
  /// Não usa [guarda]: é chamado a partir de caminhos de erro (incluindo o do
  /// próprio [login]) e uma falha a fechar a sessão não pode substituir o erro
  /// original, que é o que interessa a quem está a olhar para o ecrã.
  Future<void> logout() async {
    _utilizadorAtual = null;
    SessaoLocal.marcarTerminoIntencional();
    try {
      await client.auth.signOut();
    } catch (_) {
      // A sessão local é sempre descartada pelo SDK, mesmo que o pedido de
      // revogação ao servidor falhe por falta de rede.
    }
  }

  /// Retoma uma sessão já existente, revalidando a aprovação da conta.
  ///
  /// Devolve `null` quando não há sessão, quando a conta deixou de estar ativa
  /// ou quando o perfil não pôde ser lido — em qualquer desses casos o destino é
  /// o ecrã de login, e não há nada de útil a dizer sobre a diferença.
  Future<UtilizadorModel?> verificarSessaoAtiva() async {
    final Session? sessao = client.auth.currentSession;
    if (sessao == null) return null;

    try {
      final perfil = await obterUtilizadorPorId(sessao.user.id);

      if (perfil.estadoConta != EstadoConta.ativo) {
        await logout();
        return null;
      }

      _utilizadorAtual = perfil;
      return perfil;
    } catch (_) {
      _utilizadorAtual = null;
      return null;
    }
  }
}
