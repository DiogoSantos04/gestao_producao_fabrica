import '../models/incidencia_model.dart';
import 'base_repository.dart';

/// Acessos do terminal de manutenção.
///
/// A fila é a das incidências que ainda bloqueiam a linha; o ciclo de aceitar e
/// fechar passa por RPCs, porque as regras (quem pode pegar no trabalho, o que
/// tem de estar preenchido para o fechar) têm de valer também para quem chame a
/// API diretamente.
class TecnicoRepository extends BaseRepository {
  /// Projeção da fila: a incidência com a ordem, o posto e o motivo.
  static const String _select = '''
        *,
        encomendas:encomenda_id (
          id,
          codigo_rastreio,
          prioridade,
          data_entrega,
          clientes (nome_cliente),
          tipos_produto:tipos_produtos_id (nome_tipo_produto)
        ),
        postos_trabalho:posto_trabalho_id (nome_posto),
        reason_codes:reason_code_id (categoria, descricao),
        utilizadores:tecnico_id (nome_utilizador)
      ''';

  /// Incidências por resolver: as pendentes e as que já estão em intervenção.
  ///
  /// Inclui de propósito o trabalho já aceite por outro técnico — quem está a
  /// tratar do quê é informação de turno, e escondê-la levaria dois técnicos ao
  /// mesmo posto. Quem não pode agir é travado no botão, não na lista.
  ///
  /// As já concluídas ficam de fora: a partir daí a bola está do lado da
  /// qualidade, no Line Clearance.
  Future<List<IncidenciaModel>> obterFila() {
    return guarda('carregar a fila de manutenção', () async {
      final dados = await client
          .from('incidencias')
          .select(_select)
          .eq('manutencao_concluida', false)
          .eq('line_clearance_validado', false)
          .order('data_registo', ascending: true);
      return comoLista(dados).map(IncidenciaModel.fromJson).toList();
    });
  }

  /// Intervenções que este técnico já fechou, mais recentes primeiro.
  Future<List<IncidenciaModel>> obterHistorico({int limite = 50}) {
    return guarda('carregar o histórico de intervenções', () async {
      final id = utilizadorAtualId;
      if (id == null) return <IncidenciaModel>[];

      final dados = await client
          .from('incidencias')
          .select(_select)
          .eq('tecnico_id', id)
          .eq('manutencao_concluida', true)
          .order('data_fim_manutencao', ascending: false)
          .limit(limite);
      return comoLista(dados).map(IncidenciaModel.fromJson).toList();
    });
  }

  /// Fluxo das notificações deste técnico.
  ///
  /// O `stream()` do Supabase devolve a lista completa a cada alteração, e não
  /// só a linha nova: quem consome tem de saber quais já mostrou.
  Stream<List<Map<String, dynamic>>> escutarNotificacoes() {
    final id = utilizadorAtualId;
    if (id == null) return const Stream.empty();

    return client
        .from('notificacoes')
        .stream(primaryKey: ['id'])
        .eq('utilizador_id', id)
        .map(comoLista);
  }

  /// Marca uma notificação como lida.
  Future<void> marcarNotificacaoLida(Object notificacaoId) {
    return guarda('marcar a notificação como lida', () async {
      await client
          .from('notificacoes')
          .update({'lida': true}).eq('id', notificacaoId);
    });
  }

  /// Assume a incidência: regista o técnico e marca o início da intervenção.
  Future<void> aceitar(int incidenciaId) {
    return guarda('aceitar a incidência', () async {
      await client.rpc(
        'aceitar_incidencia',
        params: {'p_incidencia_id': incidenciaId},
      );
    });
  }

  /// Fecha a intervenção com o relatório do técnico.
  ///
  /// A ordem não retoma aqui: fica a aguardar o Line Clearance da qualidade.
  Future<void> concluir({
    required int incidenciaId,
    required String diagnostico,
    required String acoes,
    String? pecas,
  }) {
    return guarda('concluir a intervenção', () async {
      await client.rpc('concluir_intervencao_tecnica', params: {
        'p_incidencia_id': incidenciaId,
        'p_diagnostico': diagnostico,
        'p_acoes': acoes,
        'p_pecas': pecas,
      });
    });
  }
}
