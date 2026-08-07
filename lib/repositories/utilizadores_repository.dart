import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/sessao_local.dart';
import '../core/supabase_config.dart';
import '../models/utilizador_model.dart';
import 'base_repository.dart';

/// Contas de utilizador, perfis e estados de aprovação.
class UtilizadoresRepository extends BaseRepository {
  /// Todos os utilizadores, ordenados por nome.
  ///
  /// A palavra-passe não é (nem pode ser) lida: a coluna foi eliminada e as
  /// credenciais vivem apenas no Supabase Auth. Ver bug (c) em docs/BUGS_RESOLVIDOS.md.
  Future<List<UtilizadorModel>> obterTodos() {
    return guarda('carregar os utilizadores', () async {
      final dados = await client
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, email, perfil, estado_conta')
          .order('nome_utilizador');
      return comoLista(dados).map(UtilizadorModel.fromJson).toList();
    });
  }

  /// Lista para atribuição de intervenções técnicas.
  ///
  /// Restringe-se a quem tem o perfil de manutenção: antes devolvia toda a
  /// tabela, pelo que o dropdown do registo técnico deixava atribuir uma
  /// intervenção a um cliente. Aceita a grafia com e sem acento porque a coluna
  /// `perfil` é texto livre.
  Future<List<Map<String, dynamic>>> obterParaAtribuicao() {
    return guarda('carregar os técnicos', () async {
      final dados = await client
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador, perfil')
          .or('perfil.ilike.tecnico,perfil.ilike.técnico')
          .order('nome_utilizador');
      return comoLista(dados);
    });
  }

  /// Apenas utilizadores com perfil de operador.
  Future<List<Map<String, dynamic>>> obterOperadores() {
    return guarda('carregar os operadores', () async {
      final dados = await client
          .from('utilizadores')
          .select('utilizador_id, nome_utilizador')
          .ilike('perfil', 'operador')
          .order('nome_utilizador', ascending: true);
      return comoLista(dados);
    });
  }

  /// Métricas de atividade de um colaborador.
  Future<Map<String, dynamic>> obterMetricas(String utilizadorId) {
    return guarda('carregar as métricas do utilizador', () async {
      final resultados = await Future.wait([
        client
            .from('historico_producao')
            .select('data_conclusao')
            .eq('utilizador_id', utilizadorId)
            .order('data_conclusao', ascending: false),
        client.from('incidencias').select('id').eq('tecnico_id', utilizadorId),
      ]);

      final historico = comoLista(resultados[0]);
      final incidencias = comoLista(resultados[1]);

      return {
        'fasesConcluidas': historico.length,
        'ultimaAtividade': historico.isNotEmpty ? historico.first['data_conclusao'] : null,
        'incidencias': incidencias.length,
      };
    });
  }

  /// Atualiza nome, perfil e estado. O email não é alterado aqui — é a
  /// credencial gerida pelo Auth.
  Future<void> atualizar({
    required String utilizadorId,
    required String nome,
    required String perfil,
    required String estadoConta,
  }) {
    return guarda('atualizar o utilizador', () async {
      await client.from('utilizadores').update({
        'nome_utilizador': nome,
        'perfil': perfil,
        'estado_conta': estadoConta,
      }).eq('utilizador_id', utilizadorId);
    });
  }

  Future<void> alterarEstadoConta({
    required String utilizadorId,
    required String estadoConta,
  }) {
    return guarda('alterar o estado da conta', () async {
      await client
          .from('utilizadores')
          .update({'estado_conta': estadoConta})
          .eq('utilizador_id', utilizadorId);
    });
  }

  /// Cria a conta de um funcionário sem afetar a sessão do administrador.
  ///
  /// Usa um cliente Supabase isolado e temporário: um `signUp` no cliente
  /// partilhado substituiria a sessão ativa pela do novo utilizador.
  Future<void> criarFuncionario({
    required String nome,
    required String email,
    required String password,
  }) {
    return guarda('criar o funcionário', () async {
      final tempClient = SupabaseClient(
        SupabaseConfig.url,
        SupabaseConfig.publishableKey,
        // Fluxo 'implicit' evita o PKCE, que exigiria asyncStorage neste cliente
        // isolado. Aqui só criamos a conta, não persistimos sessão.
        authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
      );
      try {
        final AuthResponse res = await tempClient.auth.signUp(
          email: email,
          password: password,
          data: {'nome_utilizador': nome},
        );
        final novoUser = res.user;
        if (novoUser == null) {
          throw const RepositoryException('Não foi possível criar a credencial do funcionário.');
        }

        // A linha de perfil já foi criada pelo trigger, como
        // 'Cliente'/'Pendente'. A promoção a operador ativo é feita pelo cliente
        // partilhado, que é o que tem a sessão do administrador: o cliente
        // temporário está autenticado como o próprio funcionário e o trigger
        // `trg_impedir_autopromocao` recusaria a alteração — que é exatamente o
        // que se quer, porque é o que impede uma conta de se promover a si mesma.
        await client.from('utilizadores').update({
          'nome_utilizador': nome,
          'perfil': 'Operador',
          'estado_conta': 'Ativo',
        }).eq('utilizador_id', novoUser.id);
      } finally {
        await tempClient.dispose();
      }
    });
  }

  /// Regista um pedido de acesso feito pelo próprio, a aguardar aprovação.
  ///
  /// O perfil **não** é inserido aqui: é o trigger `trg_criar_perfil_utilizador`
  /// (em `auth.users`) que cria a linha de `utilizadores`, na mesma transação da
  /// credencial. Enquanto foram dois passos do lado do cliente, uma falha no
  /// segundo deixava uma credencial sem perfil — impossível de recuperar pela
  /// aplicação, porque o email já existia no Auth. O nome vai em metadados, que é
  /// o que o trigger lê.
  ///
  /// A conta nasce sempre `Cliente`/`Pendente`. O `estado_conta` é o campo que o
  /// `AuthService` usa como travão de login; o `perfil` guarda um papel real, que
  /// o administrador ajusta ao aprovar.
  ///
  /// Fecha a sessão que o `signUp` abre: uma conta por aprovar não pode ficar
  /// autenticada.
  Future<void> registarPedidoDeAcesso({
    required String nome,
    required String email,
    required String password,
  }) {
    return guarda('solicitar o registo', () async {
      // A palavra-passe não é gravada em `utilizadores`: vive apenas no Auth.
      final AuthResponse res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'nome_utilizador': nome},
      );

      if (res.user == null) {
        throw const RepositoryException(
          'Não foi possível criar a credencial de acesso.',
        );
      }

      await _terminarSessao();
    });
  }

  /// Fecha a sessão aberta pelo `signUp`, sem que o vigilante a confunda com
  /// uma perda de sessão involuntária.
  Future<void> _terminarSessao() async {
    SessaoLocal.marcarTerminoIntencional();
    try {
      await client.auth.signOut();
    } catch (_) {
      // A sessão local é descartada pelo SDK mesmo que a revogação falhe.
    }
  }

  /// Altera a palavra-passe do utilizador autenticado, apenas no Auth.
  Future<void> alterarPalavraPasse(String novaPalavraPasse) {
    return guarda('alterar a palavra-passe', () async {
      await client.auth.updateUser(UserAttributes(password: novaPalavraPasse));
    });
  }

  /// Perfil do utilizador autenticado, em tempo real.
  Stream<List<Map<String, dynamic>>>? escutarPerfilAtual() {
    final uid = utilizadorAtualId;
    if (uid == null) return null;
    return client
        .from('utilizadores')
        .stream(primaryKey: ['utilizador_id'])
        .eq('utilizador_id', uid);
  }
}
