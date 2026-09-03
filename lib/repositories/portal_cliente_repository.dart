import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/paginacao.dart';
import '../models/cliente_model.dart';
import '../models/encomenda_model.dart';
import '../models/notificacao_model.dart';
import '../models/pedido_model.dart';
import 'base_repository.dart';

/// Uma fase do roteiro tal como é mostrada na linha temporal do rastreio.
class FaseRoteiro {
  final int id;
  final String nome;
  final int ordem;

  const FaseRoteiro({required this.id, required this.nome, required this.ordem});

  factory FaseRoteiro.fromJson(Map<String, dynamic> json) => FaseRoteiro(
        id: (json['id'] as num).toInt(),
        nome: (json['nome_fase_padrao'] as String?) ?? 'Fase',
        ordem: (json['ordem'] as num?)?.toInt() ?? 0,
      );
}

/// Resultado do rastreio público de uma encomenda.
///
/// Deliberadamente **não** tem cliente, observações nem motivo de cancelamento:
/// a função `rastrear_encomenda` no servidor não os devolve (ver bug (C)).
class RastreioEncomenda {
  /// Identificador da encomenda, necessário para confirmar a receção.
  final int? id;

  final String codigoRastreio;
  final DateTime? dataEntrega;
  final String? nomeProduto;
  final int? faseAtualId;
  final bool cancelada;
  final bool emSuspenso;

  /// Momento em que o cliente confirmou ter recebido a encomenda.
  ///
  /// Deliberadamente **não** é um valor de [EstadoOrdem]: a receção é um passo
  /// logístico posterior ao fabrico, e não um estado de produção. Acrescentá-la
  /// ao enum faria `derivar()` deixar de devolver `concluida` para estas ordens,
  /// e todo o código que compara com `EstadoOrdem.concluida` — relatórios e
  /// KPIs — passaria a excluí-las sem dar erro. É a forma exata do bug (b) em
  /// docs/BUGS_RESOLVIDOS.md.
  final DateTime? dataConfirmacaoRececao;

  final List<FaseRoteiro> fases;

  const RastreioEncomenda({
    this.id,
    required this.codigoRastreio,
    this.dataEntrega,
    this.nomeProduto,
    this.faseAtualId,
    this.cancelada = false,
    this.emSuspenso = false,
    this.dataConfirmacaoRececao,
    this.fases = const [],
  });

  /// O cliente já confirmou a receção física.
  bool get rececaoConfirmada => dataConfirmacaoRececao != null;

  factory RastreioEncomenda.fromJson(Map<String, dynamic> json) {
    final fases = (json['fases'] as List? ?? const [])
        .whereType<Map>()
        .map((f) => FaseRoteiro.fromJson(Map<String, dynamic>.from(f)))
        .toList()
      ..sort((a, b) => a.ordem.compareTo(b.ordem));

    return RastreioEncomenda(
      id: (json['id'] as num?)?.toInt(),
      codigoRastreio: (json['codigo_rastreio'] as String?) ?? '',
      dataEntrega: DateTime.tryParse(json['data_entrega']?.toString() ?? ''),
      nomeProduto: json['nome_tipo_produto'] as String?,
      faseAtualId: (json['fase_atual_id'] as num?)?.toInt(),
      cancelada: json['cancelada'] == true,
      emSuspenso: json['em_suspenso'] == true,
      dataConfirmacaoRececao:
          DateTime.tryParse(json['data_confirmacao_rececao']?.toString() ?? ''),
      fases: fases,
    );
  }

  /// Índice da fase em curso dentro de [fases], ou `null` se não for possível
  /// determiná-lo.
  ///
  /// Devolve `null` — e não um palpite — quando a `fase_atual_id` da encomenda
  /// não pertence ao roteiro atual do produto, situação que acontece sempre que
  /// o roteiro é editado depois da ordem ter sido lançada. Marcar nesse caso
  /// todas as fases como concluídas era o comportamento antigo, e mentia ao
  /// cliente (é o defeito equivalente ao corrigido no terminal do operador).
  int? get indiceFaseAtual {
    if (faseAtualId == null) return null;
    final i = fases.indexWhere((f) => f.id == faseAtualId);
    return i < 0 ? null : i;
  }

  /// A `fase_atual_id` aponta para uma fase que já não está no roteiro.
  bool get faseAtualDesconhecida => faseAtualId != null && indiceFaseAtual == null;
}

/// Tipo de produto reduzido ao que o formulário de pedido precisa.
class TipoProdutoOpcao {
  final int id;
  final String nome;

  const TipoProdutoOpcao({required this.id, required this.nome});

  factory TipoProdutoOpcao.fromJson(Map<String, dynamic> json) => TipoProdutoOpcao(
        id: (json['id'] as num).toInt(),
        nome: (json['nome_tipo_produto'] as String?) ?? 'Artigo',
      );
}

/// Dados que o portal do cliente lê e escreve.
///
/// Os quatro ecrãs do portal falavam diretamente com o Supabase e resolviam a
/// identidade do cliente comparando `utilizadores.nome_utilizador` com
/// `clientes.nome_cliente` — ver bug (A). A identidade passa a sair de
/// [obterClienteAutenticado], que segue a chave estrangeira
/// `clientes.utilizador_id`, e existe num único sítio.
/// Uma encomenda concluída à espera de confirmação de receção pelo cliente.
///
/// Deliberadamente magra: o painel do portal só precisa de identificar a
/// encomenda ao cliente para ele reconhecer o que recebeu.
class EncomendaPorConfirmar {
  final int id;
  final String codigoRastreio;
  final String? nomeProduto;
  final int? quantidade;

  /// Data de entrega prevista — não é prova de entrega, é só a referência que
  /// ajuda o cliente a situar de que encomenda se trata.
  final DateTime? dataEntrega;

  const EncomendaPorConfirmar({
    required this.id,
    required this.codigoRastreio,
    this.nomeProduto,
    this.quantidade,
    this.dataEntrega,
  });

  factory EncomendaPorConfirmar.fromJson(Map<String, dynamic> json) {
    final produto = json['tipos_produto'];

    return EncomendaPorConfirmar(
      id: (json['id'] as num).toInt(),
      codigoRastreio: (json['codigo_rastreio'] as String?) ?? 'Sem código',
      nomeProduto:
          produto is Map ? produto['nome_tipo_produto'] as String? : null,
      quantidade: (json['quantidade'] as num?)?.toInt(),
      dataEntrega: DateTime.tryParse(json['data_entrega']?.toString() ?? ''),
    );
  }
}

class PortalClienteRepository extends BaseRepository {
  /// Cliente associado à sessão atual, ou `null` se a conta não estiver
  /// associada a nenhum registo da carteira.
  Future<ClienteModel?> obterClienteAutenticado() {
    return guarda('identificar o seu registo de cliente', () async {
      final id = utilizadorAtualId;
      if (id == null) return null;

      final dados = await client
          .from('clientes')
          .select('id, nome_cliente, contacto, email, ativo, nif, pessoa_contacto, morada, utilizador_id')
          .eq('utilizador_id', id)
          .maybeSingle();

      if (dados == null) return null;
      return ClienteModel.fromJson(Map<String, dynamic>.from(dados));
    });
  }

  /// Uma página do histórico de encomendas do cliente, mais recentes primeiro.
  ///
  /// Traz `cancelada` e `em_suspenso` para que o estado apresentado saia de
  /// [EstadoOrdem] em vez de ser adivinhado pelo nome da fase — ver bug (B).
  ///
  /// Pede uma linha a mais do que o tamanho pedido, que serve de sonda para
  /// saber se ainda há resultados — o mesmo mecanismo dos restantes módulos.
  Future<PaginaResultado<EncomendaModel>> obterEncomendas(
    int clienteId, {
    int deslocamento = 0,
    int tamanho = tamanhoPaginaPadrao,
  }) {
    return guarda('carregar o histórico de encomendas', () async {
      final dados = await client
          .from('encomendas')
          .select('''
            id,
            created_at,
            codigo_rastreio,
            data_entrega,
            tipos_produtos_id,
            fase_atual_id,
            quantidade,
            cancelada,
            motivo_cancelamento,
            em_suspenso,
            tipos_produto ( nome_tipo_produto ),
            fase_atual:fase_atual_id ( nome_fase_padrao, ordem )
          ''')
          .eq('cliente_id', clienteId)
          .order('created_at', ascending: false)
          .range(deslocamento, deslocamento + tamanho);

      return PaginaResultado.aPartirDeSondagem(
        comoLista(dados).map(EncomendaModel.fromJson).toList(),
        tamanho,
      );
    });
  }

  /// Encomendas que saíram da fábrica e o cliente ainda não confirmou receber.
  ///
  /// O pedido de confirmação viajava só por email, e o email não chega a toda a
  /// gente — o remetente pode não estar verificado, a mensagem pode cair em
  /// spam, o cliente pode não a ler. Trazer a lista para dentro do portal torna
  /// o pedido visível a quem entra, sem depender de nada externo.
  ///
  /// O filtro `fase_atual_id is null` é o mesmo critério de conclusão que
  /// [EstadoOrdem.derivar] usa; as canceladas ficam de fora porque nunca
  /// chegaram a ser entregues.
  Future<List<EncomendaPorConfirmar>> obterPorConfirmar(int clienteId) {
    return guarda('carregar as entregas por confirmar', () async {
      final dados = await client
          .from('encomendas')
          .select('''
            id,
            codigo_rastreio,
            quantidade,
            data_entrega,
            tipos_produto ( nome_tipo_produto )
          ''')
          .eq('cliente_id', clienteId)
          .isFilter('fase_atual_id', null)
          .isFilter('data_confirmacao_rececao', null)
          .eq('cancelada', false)
          .order('data_entrega', ascending: false);

      return comoLista(dados).map(EncomendaPorConfirmar.fromJson).toList();
    });
  }

  /// Identificadores das encomendas que este cliente já avaliou.
  Future<Set<int>> obterEncomendasAvaliadas(int clienteId) {
    return guarda('verificar as avaliações já submetidas', () async {
      final dados = await client
          .from('avaliacoes')
          .select('encomenda_id')
          .eq('cliente_id', clienteId);

      return comoLista(dados)
          .map((a) => (a['encomenda_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
    });
  }

  /// Regista a avaliação de uma encomenda entregue.
  ///
  /// `data_registo` fica a cargo do servidor (`DEFAULT CURRENT_DATE`):
  /// calculá-la com o relógio do dispositivo do cliente dava datas erradas em
  /// máquinas desacertadas. Um comentário vazio é gravado como `NULL` — a
  /// coluna aceita-o, ao contrário do que o comentário do ecrã afirmava.
  Future<void> registarAvaliacao({
    required int encomendaId,
    required int clienteId,
    required int nota,
    required String comentario,
  }) {
    return guarda('submeter a avaliação', () async {
      final texto = comentario.trim();
      try {
        await client.from('avaliacoes').insert({
          'encomenda_id': encomendaId,
          'cliente_id': clienteId,
          'nota': nota,
          'comentario': texto.isEmpty ? null : texto,
        });
      } on PostgrestException catch (e) {
        // 23505: o índice único `avaliacoes_encomenda_cliente_key` recusou uma
        // segunda avaliação da mesma encomenda. O texto do Postgres não serve
        // para mostrar ao cliente.
        if (e.code == '23505') {
          throw const RepositoryException('Esta encomenda já foi avaliada.');
        }
        rethrow;
      }
    });
  }

  /// Artigos que o cliente pode encomendar, por ordem alfabética.
  Future<List<TipoProdutoOpcao>> obterTiposProduto() {
    return guarda('carregar os artigos disponíveis', () async {
      final dados = await client
          .from('tipos_produto')
          .select('id, nome_tipo_produto')
          .order('nome_tipo_produto');

      return comoLista(dados).map(TipoProdutoOpcao.fromJson).toList();
    });
  }

  /// Submete um pedido de encomenda para análise do administrador.
  Future<void> submeterPedido({
    required int clienteId,
    required int tipoProdutoId,
    required int quantidade,
    required String observacoes,
  }) {
    return guarda('submeter o pedido de encomenda', () async {
      final obs = observacoes.trim();
      await client.from('pedidos_encomenda').insert({
        'cliente_id': clienteId,
        'tipo_produto_id': tipoProdutoId,
        'quantidade': quantidade,
        'observacoes': obs.isEmpty ? null : obs,
        'estado': EstadoPedido.pendente.valorBd,
      });
    });
  }

  // --- NOTIFICAÇÕES ---

  /// Fluxo das notificações do utilizador autenticado, das mais recentes para
  /// as mais antigas.
  ///
  /// Devolve a lista completa a cada alteração, e não apenas a linha nova — é
  /// como o `stream()` do Supabase funciona. Quem consome tem de saber quais já
  /// mostrou ao vivo; ver [marcarNotificacaoLida].
  ///
  /// A ordenação é feita aqui e não no servidor porque `stream()` só ordena
  /// pela chave primária.
  Stream<List<NotificacaoModel>> escutarNotificacoes() {
    final id = utilizadorAtualId;
    if (id == null) return const Stream.empty();

    return client
        .from('notificacoes')
        .stream(primaryKey: ['id'])
        .eq('utilizador_id', id)
        .map((linhas) {
      final notificacoes = comoLista(linhas).map(NotificacaoModel.fromJson).toList();
      notificacoes.sort((a, b) {
        final da = a.criadaEm;
        final db = b.criadaEm;
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
      return notificacoes;
    });
  }

  /// Marca uma notificação como lida.
  Future<void> marcarNotificacaoLida(Object notificacaoId) {
    return guarda('marcar a notificação como lida', () async {
      await client.from('notificacoes').update({'lida': true}).eq('id', notificacaoId);
    });
  }

  /// Marca como lidas todas as notificações por ler do utilizador.
  ///
  /// O filtro por `lida` evita reescrever linhas que já estão certas — sem ele,
  /// cada utilização reemitia o stream inteiro sem nada ter mudado.
  Future<void> marcarTodasNotificacoesLidas() {
    return guarda('marcar as notificações como lidas', () async {
      final id = utilizadorAtualId;
      if (id == null) return;

      await client
          .from('notificacoes')
          .update({'lida': true})
          .eq('utilizador_id', id)
          .eq('lida', false);
    });
  }

  /// Perfil do utilizador autenticado (nome e email), em tempo real.
  Stream<Map<String, dynamic>?> escutarPerfil() {
    final id = utilizadorAtualId;
    if (id == null) return const Stream.empty();

    return client
        .from('utilizadores')
        .stream(primaryKey: ['utilizador_id'])
        .eq('utilizador_id', id)
        .map((linhas) => linhas.isEmpty ? null : Map<String, dynamic>.from(linhas.first));
  }

  /// Escuta as alterações que afetam o que o cliente vê: as suas encomendas
  /// (mudança de fase, conclusão, cancelamento) e os seus pedidos.
  RealtimeChannel escutarAtividadeDoCliente(String canal, void Function() aoAlterar) {
    return client
        .channel(canal)
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

  // --- PEDIDOS DO PRÓPRIO CLIENTE ---

  /// Pedidos submetidos por este cliente, mais recentes primeiro.
  Future<List<PedidoModel>> obterMeusPedidos(int clienteId) {
    return guarda('carregar os seus pedidos', () async {
      final dados = await client
          .from('pedidos_encomenda')
          .select('id, quantidade, observacoes, estado, created_at, cliente_id, '
              'tipo_produto_id, tipos_produto:tipo_produto_id(nome_tipo_produto)')
          .eq('cliente_id', clienteId)
          .order('created_at', ascending: false);

      return comoLista(dados).map(PedidoModel.fromJson).toList();
    });
  }

  /// Rastreio público de uma encomenda pelo código.
  ///
  /// Passa pela função `rastrear_encomenda` (SECURITY DEFINER) em vez de ler a
  /// tabela: a consulta direta devolvia o nome do cliente destinatário a quem
  /// tivesse — ou adivinhasse — um código de rastreio.
  Future<RastreioEncomenda?> rastrear(String codigo) {
    return guarda('consultar o rastreio', () async {
      final resposta = await client.rpc(
        'rastrear_encomenda',
        params: {'p_codigo': codigo.trim()},
      );

      if (resposta == null) return null;
      return RastreioEncomenda.fromJson(Map<String, dynamic>.from(resposta as Map));
    });
  }

  /// Confirma a receção física de uma encomenda concluída.
  ///
  /// Fecha a rastreabilidade do lado do destinatário: até aqui o percurso de uma
  /// ordem terminava na fábrica, com a última fase concluída, e nada registava
  /// que ela tinha efetivamente chegado.
  ///
  /// Ao contrário de [rastrear], **exige sessão iniciada**. O rastreio é
  /// consultável por quem tenha o código, mas confirmar é um ato de vontade do
  /// destinatário: a função no servidor compara o dono da encomenda com
  /// `cliente_atual_id()` e recusa tudo o resto. Devolve o momento gravado pelo
  /// relógio do servidor.
  Future<DateTime?> confirmarRececao(int encomendaId) {
    return guarda('confirmar a receção da encomenda', () async {
      final resposta = await client.rpc(
        'confirmar_rececao_encomenda',
        params: {'p_encomenda_id': encomendaId},
      );

      return DateTime.tryParse(resposta?.toString() ?? '');
    });
  }

  /// Email de contacto do administrador, para o botão "Contactar Suporte".
  ///
  /// Passa pela função `obter_email_suporte` (SECURITY DEFINER): a política de
  /// RLS de `utilizadores` só deixa um cliente ler a sua própria linha, e não
  /// há (ainda) um email geral da empresa — é sempre o do administrador ativo.
  Future<String?> obterEmailSuporte() {
    return guarda('obter o contacto de suporte', () async {
      final resposta = await client.rpc('obter_email_suporte');
      return resposta as String?;
    });
  }
}
