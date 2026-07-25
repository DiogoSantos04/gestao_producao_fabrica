import 'package:supabase_flutter/supabase_flutter.dart';
import 'base_repository.dart';

/// Carteira de clientes e pedidos submetidos pelo portal B2B.
class ClientesRepository extends BaseRepository {
  // --- CLIENTES ---

  /// Clientes com o histórico de encomendas e os pedidos da app.
  Future<List<Map<String, dynamic>>> obterComHistorico() {
    return guarda('carregar a base de dados de clientes', () async {
      final dados = await client
          .from('clientes')
          .select('id, nome_cliente, contacto, email, ativo, nif, pessoa_contacto, morada, '
              'encomendas(id, codigo_rastreio, data_entrega, quantidade, prioridade, '
              'tipos_produto:tipos_produtos_id(nome_tipo_produto)), '
              'pedidos_encomenda(id, quantidade, observacoes, estado, '
              'tipos_produto:tipo_produto_id(nome_tipo_produto))')
          .order('nome_cliente', ascending: true);
      return comoLista(dados);
    });
  }

  /// Versão reduzida para dropdowns.
  Future<List<Map<String, dynamic>>> obterParaSelecao() {
    return guarda('carregar os clientes', () async {
      final dados = await client
          .from('clientes')
          .select('id, nome_cliente')
          .order('nome_cliente', ascending: true);
      return comoLista(dados);
    });
  }

  Future<void> criar(Map<String, dynamic> dados) {
    return guarda('criar o cliente', () async {
      await client.from('clientes').insert(dados);
    });
  }

  Future<void> atualizar({required int id, required Map<String, dynamic> dados}) {
    return guarda('atualizar o cliente', () async {
      await client.from('clientes').update(dados).eq('id', id);
    });
  }

  // --- PEDIDOS DO PORTAL B2B ---

  /// Todos os pedidos com cliente e produto, mais recentes primeiro.
  Future<List<Map<String, dynamic>>> obterPedidos() {
    return guarda('carregar os pedidos', () async {
      final dados = await client
          .from('pedidos_encomenda')
          .select('''
            id,
            quantidade,
            observacoes,
            estado,
            created_at,
            cliente_id,
            tipo_produto_id,
            clientes ( id, nome_cliente, email ),
            tipos_produto ( id, nome_tipo_produto )
          ''')
          .order('created_at', ascending: false);
      return comoLista(dados);
    });
  }

  /// Pedidos já aprovados que aguardam agendamento de produção.
  Future<List<Map<String, dynamic>>> obterPedidosAprovados() {
    return guarda('carregar os pedidos aprovados', () async {
      final dados = await client
          .from('pedidos_encomenda')
          .select('id, quantidade, observacoes, estado, cliente_id, tipo_produto_id, '
              'clientes(nome_cliente), tipos_produto:tipo_produto_id(nome_tipo_produto)')
          .or('estado.ilike.Aprovado%,estado.eq.Aprovado')
          .order('id', ascending: false);
      return comoLista(dados);
    });
  }

  /// Aprova o pedido e lança a ordem de produção numa única transação.
  Future<void> aprovarPedido({
    required int pedidoId,
    required String dataEntrega,
    required String codigoRastreio,
  }) {
    return guarda('aprovar o pedido', () async {
      await client.rpc('aprovar_pedido_encomenda', params: {
        'p_pedido_id': pedidoId,
        'p_data_entrega': dataEntrega,
        'p_codigo_rastreio': codigoRastreio,
      });
    });
  }

  Future<void> rejeitarPedido(int pedidoId) {
    return guarda('rejeitar o pedido', () async {
      await client.from('pedidos_encomenda').update({'estado': 'Rejeitado'}).eq('id', pedidoId);
    });
  }

  Future<void> marcarPedidoEmProducao(int pedidoId) {
    return guarda('atualizar o estado do pedido', () async {
      await client.from('pedidos_encomenda').update({'estado': 'Em Produção'}).eq('id', pedidoId);
    });
  }

  /// Escuta alterações em clientes, encomendas e pedidos.
  RealtimeChannel escutarCarteira(String canal, void Function() aoAlterar) {
    return client
        .channel(canal)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clientes',
          callback: (_) => aoAlterar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encomendas',
          callback: (_) => aoAlterar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos_encomenda',
          callback: (_) => aoAlterar(),
        )
      ..subscribe();
  }

  /// Escuta o que alimenta o ecrã de planeamento.
  RealtimeChannel escutarPlaneamento(String canal, void Function() aoAlterar) {
    return client
        .channel(canal)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos_encomenda',
          callback: (_) => aoAlterar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tipos_produto',
          callback: (_) => aoAlterar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clientes',
          callback: (_) => aoAlterar(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'encomendas',
          callback: (_) => aoAlterar(),
        )
      ..subscribe();
  }
}
