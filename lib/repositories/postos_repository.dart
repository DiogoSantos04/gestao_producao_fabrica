import 'package:supabase_flutter/supabase_flutter.dart';
import 'base_repository.dart';

/// Estados persistidos na coluna `postos_trabalho.estado`.
///
/// Têm de coincidir exatamente com o CHECK definido na base de dados. Estavam
/// escritos à mão no ecrã com valores diferentes dos aceites, o que fazia falhar
/// todos os updates em silêncio — ver bug (a) em docs/BUGS_RESOLVIDOS.md.
abstract class EstadoPosto {
  static const String livre = 'Livre';
  static const String emProducao = 'Em Produção';
  static const String parado = 'Parado';
}

/// Acesso aos postos de trabalho da fábrica.
class PostosRepository extends BaseRepository {
  /// Postos com o operador atribuído.
  Future<List<Map<String, dynamic>>> obterTodos() {
    return guarda('carregar os postos de trabalho', () async {
      final dados = await client
          .from('postos_trabalho')
          .select('*, utilizadores:operador_id(utilizador_id, nome_utilizador)')
          .order('id', ascending: true);
      return comoLista(dados);
    });
  }

  /// Mapa `operador_id -> posto`, apenas para postos com operador atribuído.
  /// Usado pela gestão de utilizadores para mostrar a afetação de cada operador.
  Future<Map<String, Map<String, dynamic>>> obterPorOperador() {
    return guarda('carregar a afetação dos operadores', () async {
      final dados = await client
          .from('postos_trabalho')
          .select('id, nome_posto, estado, operador_id')
          .not('operador_id', 'is', null);

      final mapa = <String, Map<String, dynamic>>{};
      for (final p in comoLista(dados)) {
        final opId = p['operador_id']?.toString();
        if (opId != null) mapa[opId] = p;
      }
      return mapa;
    });
  }

  Future<void> atribuirOperador({
    required int postoId,
    required String? operadorId,
    required String estado,
  }) {
    return guarda('atualizar o operador do posto', () async {
      await client.from('postos_trabalho').update({
        'operador_id': operadorId,
        'estado': estado,
      }).eq('id', postoId);
    });
  }

  Future<void> alterarEstado({required int postoId, required String estado}) {
    return guarda('alterar o estado do posto', () async {
      await client.from('postos_trabalho').update({'estado': estado}).eq('id', postoId);
    });
  }

  /// Escuta alterações na tabela `postos_trabalho`.
  RealtimeChannel escutar(String canal, void Function() aoAlterar) {
    return client
        .channel(canal)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'postos_trabalho',
          callback: (_) => aoAlterar(),
        )
      ..subscribe();
  }
}
