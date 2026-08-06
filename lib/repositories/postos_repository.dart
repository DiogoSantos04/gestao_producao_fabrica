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

/// Um posto de trabalho reduzido ao que o dashboard precisa.
class PostoResumo {
  final int id;
  final String nome;
  final String estado;

  const PostoResumo({required this.id, required this.nome, required this.estado});

  /// Identificador do balde das ordens cuja fase não aponta para posto nenhum.
  /// Negativo porque `postos_trabalho.id` é uma sequência positiva.
  static const int idSemPosto = -1;

  bool get parado => estado == EstadoPosto.parado;
}

/// Quantas ordens estão paradas num posto físico, agora.
class OcupacaoPosto {
  final PostoResumo posto;
  final int ordens;

  const OcupacaoPosto({required this.posto, required this.ordens});
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

  /// Os postos físicos da fábrica, pela ordem em que foram criados.
  ///
  /// A coluna `estado` é a fonte de verdade do chão de fábrica — o dashboard
  /// inferia-a a partir das incidências abertas, o que ignorava postos parados
  /// sem incidência registada e contava fases em vez de postos físicos.
  ///
  /// Uma leitura só serve a disponibilidade e o gráfico de ocupação: são a
  /// mesma lista de postos vista de dois ângulos, e separá-las abriria a porta
  /// a mostrarem números incoerentes entre si.
  Future<List<PostoResumo>> obterResumo() {
    return guarda('carregar o estado dos postos', () async {
      final dados = await client
          .from('postos_trabalho')
          .select('id, nome_posto, estado')
          .order('id');

      return comoLista(dados)
          .map((p) => PostoResumo(
                id: (p['id'] as num).toInt(),
                nome: (p['nome_posto'] as String?)?.trim().isNotEmpty == true
                    ? (p['nome_posto'] as String).trim()
                    : 'Posto ${p['id']}',
                estado: (p['estado'] as String?)?.trim() ?? '',
              ))
          .toList();
    });
  }

  /// Contagem de postos por estado, para a disponibilidade do dashboard.
  static Map<String, int> contarPorEstado(List<PostoResumo> postos) {
    final contagem = <String, int>{};
    for (final p in postos) {
      if (p.estado.isEmpty) continue;
      contagem[p.estado] = (contagem[p.estado] ?? 0) + 1;
    }
    return contagem;
  }

  /// Quantas ordens ativas estão em cada posto físico.
  ///
  /// [fasesAtuais] são os `fase_atual_id` das ordens na linha (um por ordem,
  /// podendo repetir-se) e [postoPorFase] traduz cada fase no posto que a
  /// executa. O gráfico agrupava por `nome_fase_padrao`, mas o nome da fase
  /// repete-se entre roteiros de produtos diferentes: "Corte" do produto A e
  /// "Corte" do produto B caíam na mesma barra sem que exista um recurso único
  /// por trás dela. O posto é que é o recurso finito da fábrica.
  ///
  /// Postos sem ordens aparecem a zero — um posto vazio é informação. Já o
  /// balde das ordens sem posto só existe quando tem alguma coisa lá dentro.
  static List<OcupacaoPosto> distribuirOrdens({
    required List<PostoResumo> postos,
    required Map<int, int> postoPorFase,
    required List<int> fasesAtuais,
  }) {
    final contagem = <int, int>{for (final p in postos) p.id: 0};
    int semPosto = 0;

    for (final faseId in fasesAtuais) {
      final postoId = postoPorFase[faseId];
      if (postoId == null || !contagem.containsKey(postoId)) {
        // A fase não tem `posto_trabalho_id` (dados legados) ou aponta para um
        // posto entretanto apagado. A ordem existe na mesma e some-la a um
        // posto qualquer seria pior do que dizer que não está atribuída.
        semPosto++;
        continue;
      }
      contagem[postoId] = contagem[postoId]! + 1;
    }

    final ocupacao = [
      for (final p in postos) OcupacaoPosto(posto: p, ordens: contagem[p.id]!),
    ];

    if (semPosto > 0) {
      ocupacao.add(OcupacaoPosto(
        posto: const PostoResumo(
          id: PostoResumo.idSemPosto,
          nome: 'Sem posto',
          estado: '',
        ),
        ordens: semPosto,
      ));
    }
    return ocupacao;
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
