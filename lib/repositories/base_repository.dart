import 'package:supabase_flutter/supabase_flutter.dart';

/// Erro de domínio devolvido pelos repositórios.
///
/// Isola os ecrãs do `PostgrestException` e das mensagens do driver. As RPCs de
/// produção lançam mensagens de negócio já escritas em português — essas são
/// preservadas tal e qual, para poderem ser mostradas diretamente ao utilizador.
class RepositoryException implements Exception {
  final String mensagem;
  final Object? causa;

  const RepositoryException(this.mensagem, [this.causa]);

  @override
  String toString() => mensagem;
}

/// Base comum aos repositórios: acesso ao cliente Supabase e tradução de erros.
///
/// Antes de existir esta camada, cada um dos 10 ecrãs do dashboard chamava
/// `Supabase.instance.client` diretamente e repetia o mesmo `try/catch` com uma
/// string de erro escrita à mão. As queries ficavam espalhadas pela UI, o que
/// permitiu que a mesma entidade fosse lida de formas diferentes em ecrãs
/// diferentes (ver bug (b) em BUGS_RESOLVIDOS.md).
abstract class BaseRepository {
  SupabaseClient get client => Supabase.instance.client;

  /// Identificador do utilizador autenticado, ou `null` se não houver sessão.
  String? get utilizadorAtualId => client.auth.currentUser?.id;

  /// Email do utilizador autenticado.
  String? get utilizadorAtualEmail => client.auth.currentUser?.email;

  /// Executa uma operação traduzindo qualquer falha para [RepositoryException].
  ///
  /// [contexto] descreve a operação em linguagem de negócio (ex: "carregar as
  /// ordens de produção") e é usado para compor a mensagem quando o erro não
  /// vem já legível do servidor.
  Future<T> guarda<T>(String contexto, Future<T> Function() operacao) async {
    try {
      return await operacao();
    } on PostgrestException catch (e) {
      // As RPCs usam RAISE EXCEPTION com texto de negócio; nesse caso a mensagem
      // do servidor é melhor do que qualquer coisa que possamos compor aqui.
      throw RepositoryException(e.message, e);
    } on StorageException catch (e) {
      throw RepositoryException('Falha ao $contexto: ${e.message}', e);
    } on AuthException catch (e) {
      throw RepositoryException(e.message, e);
    } catch (e) {
      throw RepositoryException('Falha ao $contexto.', e);
    }
  }

  /// Normaliza a resposta do Supabase para uma lista de mapas tipada.
  List<Map<String, dynamic>> comoLista(dynamic resposta) {
    if (resposta is List) {
      return resposta.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }
}
