import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/paginacao.dart';
import '../models/cliente_model.dart';
import '../models/pedido_model.dart';
import 'base_repository.dart';

/// Carteira de clientes e pedidos submetidos pelo portal B2B.
class ClientesRepository extends BaseRepository {
  // --- CLIENTES ---

  /// Colunas do cliente e as junções que o painel de detalhe precisa.
  ///
  /// A junção com `encomendas` leva `!inner` quando o filtro é "com encomendas":
  /// é o que transforma o embed num critério de seleção do próprio cliente, em
  /// vez de apenas o acompanhar.
  static String _selectClientes({required bool exigirEncomendas}) =>
      'id, nome_cliente, contacto, email, ativo, nif, pessoa_contacto, morada, '
      'utilizador_id, '
      'encomendas${exigirEncomendas ? '!inner' : ''}'
      '(id, codigo_rastreio, data_entrega, quantidade, prioridade, '
      'tipos_produto:tipos_produtos_id(nome_tipo_produto)), '
      'pedidos_encomenda(id, quantidade, observacoes, estado, '
      'tipos_produto:tipo_produto_id(nome_tipo_produto))';

  /// Colunas textuais cobertas pela pesquisa — as mesmas de
  /// [ClienteModel.corresponde], que fazia esta comparação em memória.
  static const List<String> _camposPesquisa = [
    'nome_cliente',
    'email',
    'contacto',
    'nif',
    'pessoa_contacto',
    'morada',
  ];

  /// Uma fatia da carteira, com histórico de encomendas e pedidos.
  ///
  /// O filtro e a pesquisa correm no servidor: filtrar em memória sobre uma lista
  /// paginada esconderia todos os clientes que ainda não tivessem sido carregados.
  Future<PaginaResultado<ClienteModel>> obterComHistorico({
    int deslocamento = 0,
    int tamanho = tamanhoPaginaPadrao,
    FiltroCliente filtro = FiltroCliente.todos,
    String pesquisa = '',
  }) {
    return guarda('carregar a base de dados de clientes', () async {
      var query = client.from('clientes').select(
            _selectClientes(exigirEncomendas: filtro == FiltroCliente.comEncomendas),
          );

      query = switch (filtro) {
        FiltroCliente.todos || FiltroCliente.comEncomendas => query,
        FiltroCliente.ativos => query.eq('ativo', true),
        FiltroCliente.inativos => query.eq('ativo', false),
      };

      final termo = _termoPesquisa(pesquisa);
      if (termo != null) {
        query = query.or(_camposPesquisa.map((c) => '$c.ilike.%$termo%').join(','));
      }

      // Uma linha a mais do que o pedido serve de sonda para saber se ainda há
      // resultados depois desta fatia.
      final dados = await query
          .order('nome_cliente', ascending: true)
          .range(deslocamento, deslocamento + tamanho);

      return PaginaResultado.aPartirDeSondagem(
        comoLista(dados).map(ClienteModel.fromJson).toList(),
        tamanho,
      );
    });
  }

  /// Contadores do topo do ecrã, apurados sobre a carteira inteira.
  ///
  /// As duas primeiras métricas são `count` no servidor, sem trazer linhas. As
  /// duas últimas saem de uma leitura de `encomendas.cliente_id` — uma coluna de
  /// inteiros — porque o PostgREST não sabe contar valores distintos. É a tabela
  /// toda, mas apenas uma coluna: incomparavelmente mais leve do que a junção
  /// completa que alimentava estes números antes.
  Future<MetricasClientes> obterMetricas() {
    return guarda('carregar as métricas de clientes', () async {
      final total = await client.from('clientes').count(CountOption.exact);
      final ativos =
          await client.from('clientes').select('id').eq('ativo', true).count(CountOption.exact);
      final encomendas = comoLista(await client.from('encomendas').select('cliente_id'));

      // Só as encomendas com cliente entram: o total apresentado sempre foi a
      // soma das encomendas *por cliente*, e não as da tabela inteira.
      final idsClientes = encomendas.map((e) => e['cliente_id']).whereType<Object>().toList();

      return MetricasClientes(
        total: total,
        ativosPortal: ativos.count,
        comEncomendas: idsClientes.toSet().length,
        totalEncomendas: idsClientes.length,
      );
    });
  }

  /// Normaliza o termo de pesquisa, ou devolve `null` se não houver pesquisa.
  ///
  /// Vírgulas, parênteses e aspas são a sintaxe do `or()` do PostgREST — deixá-los
  /// passar partiria a query em vez de os procurar.
  static String? _termoPesquisa(String pesquisa) {
    final termo = pesquisa.trim().replaceAll(RegExp(r'[,()"]'), '');
    return termo.isEmpty ? null : termo;
  }

  /// Versão reduzida para dropdowns (só `id` e nome preenchidos).
  Future<List<ClienteModel>> obterParaSelecao() {
    return guarda('carregar os clientes', () async {
      final dados = await client
          .from('clientes')
          .select('id, nome_cliente')
          .order('nome_cliente', ascending: true);
      return comoLista(dados).map(ClienteModel.fromJson).toList();
    });
  }

  Future<void> criar(Map<String, dynamic> dados) {
    return guarda('criar o cliente', () async {
      await client.from('clientes').insert(dados);
    });
  }

  /// Cria a ficha do cliente e a sua conta de acesso ao portal, num só passo.
  ///
  /// Delegado na Edge Function `criar-cliente` por uma razão concreta: criar a
  /// credencial aqui obrigava a um `signUp`, e em Flutter web um `signUp`
  /// — mesmo num `SupabaseClient` isolado — propaga a sessão nova pelo
  /// `BroadcastChannel` do gotrue, cuja chave deriva só do URL do projeto. O
  /// administrador ficava autenticado como o cliente que acabara de criar e a
  /// escrita seguinte em `clientes` morria em violação de RLS. Ver o cabeçalho
  /// de `supabase/functions/criar-cliente/index.ts`.
  ///
  /// A função é transacional na prática: se a ficha não for gravada, a
  /// credencial criada é apagada do Auth, em vez de ficar a queimar o email.
  Future<void> criarComAcesso({
    required String nome,
    required String email,
    required String contacto,
    required String nif,
    required String pessoaContacto,
    required String morada,
    required bool ativo,
    required String password,
  }) {
    return guarda('criar o cliente', () async {
      await invocarFuncao(
        'criar-cliente',
        corpo: {
          'nome': nome,
          'email': email,
          'contacto': contacto,
          'nif': nif,
          'pessoa_contacto': pessoaContacto,
          'morada': morada,
          'ativo': ativo,
          'password': password,
        },
        erroGenerico: 'Não foi possível criar o cliente.',
      );
    });
  }

  Future<void> atualizar({required int id, required Map<String, dynamic> dados}) {
    return guarda('atualizar o cliente', () async {
      await client.from('clientes').update(dados).eq('id', id);
    });
  }

  // --- PEDIDOS DO PORTAL B2B ---

  /// Todos os pedidos com cliente e produto, mais recentes primeiro.
  Future<List<PedidoModel>> obterPedidos() {
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
      return comoLista(dados).map(PedidoModel.fromJson).toList();
    });
  }

  /// Pedidos já aprovados que aguardam agendamento de produção.
  Future<List<PedidoModel>> obterPedidosAprovados() {
    return guarda('carregar os pedidos aprovados', () async {
      final dados = await client
          .from('pedidos_encomenda')
          .select('id, quantidade, observacoes, estado, cliente_id, tipo_produto_id, '
              'clientes(nome_cliente), tipos_produto:tipo_produto_id(nome_tipo_produto)')
          .or('estado.ilike.Aprovado%,estado.eq.Aprovado')
          .order('id', ascending: false);
      return comoLista(dados).map(PedidoModel.fromJson).toList();
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
      await client
          .from('pedidos_encomenda')
          .update({'estado': EstadoPedido.rejeitado.valorBd})
          .eq('id', pedidoId);
    });
  }

  Future<void> marcarPedidoEmProducao(int pedidoId) {
    return guarda('atualizar o estado do pedido', () async {
      await client
          .from('pedidos_encomenda')
          .update({'estado': EstadoPedido.emProducao.valorBd})
          .eq('id', pedidoId);
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
