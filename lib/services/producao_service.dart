import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/encomenda_model.dart';
import '../models/fase_model.dart';

class ProducaoService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // =========================================================================
  // BLOCO 1: ENGENHARIA DE PRODUTO & FLUXOS (Tipos de Produto e Roteiros)
  // =========================================================================

  /// Obtém a lista de todos os tipos/famílias de produtos no catálogo da fábrica.
  Future<List<Map<String, dynamic>>> obterTiposProduto() async {
    try {
      final response = await _supabase
          .from('tipos_produto')
          .select('*')
          .order('id', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Erro no ProducaoService (obterTiposProduto): $e');
      throw Exception('Falha ao carregar a lista de tipos de produto.');
    }
  }

  /// Regista um novo tipo de produto no catálogo.
  Future<void> criarTipoProduto(String nomeTipoProduto) async {
    try {
      await _supabase.from('tipos_produto').insert({
        'nome_tipo_produto': nomeTipoProduto.trim(),
      });
      print('✅ Tipo de produto "$nomeTipoProduto" criado com sucesso.');
    } catch (e) {
      print('❌ Erro no ProducaoService (criarTipoProduto): $e');
      throw Exception('Falha ao criar o novo tipo de produto.');
    }
  }

  /// Procura todas as fases padrão associadas a uma tipologia de produto (Modelo Typed),
  /// ordenadas de forma rígida pela coluna 'ordem' (ex: 1, 2, 3).
  Future<List<FaseModel>> obterFasesDoProduto(int tipoProdutoId) async {
    try {
      final List<dynamic> data = await _supabase
          .from('fases_padrao')
          .select()
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem', ascending: true);

      return data.map((faseJson) => FaseModel.fromJson(faseJson)).toList();
    } catch (e) {
      print('❌ Erro no ProducaoService (obterFasesDoProduto): $e');
      throw Exception('Falha ao carregar o fluxo produtivo do produto.');
    }
  }

  /// Procura todas as fases padrão associadas a um produto (Retorno em Map para UI Admin).
  Future<List<Map<String, dynamic>>> obterFasesDoProdutoMap(int tipoProdutoId) async {
    try {
      final response = await _supabase
          .from('fases_padrao')
          .select('*')
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Erro no ProducaoService (obterFasesDoProdutoMap): $e');
      throw Exception('Falha ao carregar as fases do produto.');
    }
  }

  /// Adiciona um novo passo/operação à gama operatória (roteiro) de um artigo.
  Future<void> adicionarFasePadrao({
    required int tipoProdutoId,
    required String nomeFase,
    required int ordem,
    required int tempoEstimado,
    required String postoTrabalho,
  }) async {
    try {
      await _supabase.from('fases_padrao').insert({
        'tipos_produto_id': tipoProdutoId,
        'nome_fase_padrao': nomeFase.trim(),
        'ordem': ordem,
        'tempo_estimado': tempoEstimado,
        'posto_trabalho': postoTrabalho,
      });
      print('✅ Passo "$nomeFase" adicionado ao roteiro com sucesso (Ordem: $ordem).');
    } catch (e) {
      print('❌ Erro no ProducaoService (adicionarFasePadrao): $e');
      throw Exception('Falha ao adicionar o passo ao roteiro de produção.');
    }
  }

  /// Elimina um passo da gama operatória de um artigo.
  Future<void> removerFasePadrao(int faseId) async {
    try {
      await _supabase.from('fases_padrao').delete().eq('id', faseId);
      print('🗑️ Passo ID $faseId removido do roteiro.');
    } catch (e) {
      print('❌ Erro no ProducaoService (removerFasePadrao): $e');
      throw Exception('Falha ao remover a fase do roteiro.');
    }
  }

  // =========================================================================
  // BLOCO 2: GESTÃO DE ENCOMENDAS (Lado do Administrador)
  // =========================================================================

  /// Cria uma nova ordem de produção no sistema, gerando o registo inicial 
  /// na tabela de histórico automaticamente associado à primeira fase (ordem = 1).
  Future<void> criarNovaEncomenda({
    required String codigoRastreio,
    required DateTime dataEntrega,
    required int clienteId,
    required int tiposProdutosId,
    required String administradorId,
  }) async {
    try {
      // 1. Descobrir qual é a fase inicial (ordem = 1) configurada para este tipo de produto
      final fases = await obterFasesDoProduto(tiposProdutosId);
      if (fases.isEmpty) {
        throw Exception('Não existem fases de produção configuradas para este tipo de produto.');
      }
      final int primeiraFaseId = fases.first.id;

      // 2. Inserir o registo principal na tabela 'encomendas'
      final Map<String, dynamic> novaEncomendaData = {
        'codigo_rastreio': codigoRastreio.trim(),
        'data_entrega': "${dataEntrega.year}-${dataEntrega.month.toString().padLeft(2, '0')}-${dataEntrega.day.toString().padLeft(2, '0')}",
        'cliente_id': clienteId,
        'types_produtos_id': tiposProdutosId,
        'fase_atual_id': primeiraFaseId,
      };

      final response = await _supabase
          .from('encomendas')
          .insert(novaEncomendaData)
          .select()
          .single();

      final int encomendaCriadaId = response['id'] as int;

      // 3. Criar automaticamente o primeiro log histórico de entrada em produção (Rastreabilidade)
      await _supabase.from('historico_producao').insert({
        'encomenda_id': encomendaCriadaId,
        'fase_concluida_id': primeiraFaseId,
        'utilizador_id': administradorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      });

      print('✅ Encomenda lançada com sucesso! Código ID interno: $encomendaCriadaId');
    } catch (e) {
      print('❌ Erro no ProducaoService (criarNovaEncomenda): $e');
      throw Exception('Erro ao lançar nova ordem de produção no Supabase.');
    }
  }

  // =========================================================================
  // BLOCO 3: MÁQUINA DE ESTADOS RÍGIDA (Lado do Operador)
  // =========================================================================

  /// Avança a encomenda para a etapa seguinte do fluxo fabril de forma sequencial.
  /// Implementa regras estritas: bloqueia a ação se houver incidências em aberto.
  Future<void> avancarFase({
    required EncomendaModel encomenda,
    required String operadorId,
  }) async {
    try {
      // Rule A: Validar se a encomenda não tem bloqueios ativos na fase atual
      final List<dynamic> incidenciasAtivas = await _supabase
          .from('incidencias')
          .select('id')
          .eq('historico_producao_id', encomenda.faseAtualId ?? -1);

      if (incidenciasAtivas.isNotEmpty) {
        throw Exception('Transição negada: Esta encomenda encontra-se Bloqueada por uma incidência.');
      }

      // Rule B: Puxar a sequência linear de fases para calcular o próximo passo lógico
      final fases = await obterFasesDoProduto(encomenda.tipoProdutoId ?? -1);
      final int indiceAtual = fases.indexWhere((fase) => fase.id == encomenda.faseAtualId);

      if (indiceAtual == -1) {
        throw Exception('Fase atual da encomenda é inválida para este fluxo.');
      }

      // Rule C: Verificar se já atingiu o fim do ciclo produtivo
      if (indiceAtual >= fases.length - 1) {
        throw Exception('A encomenda já se encontra na última fase (Ciclo Concluído).');
      }

      // Seleciona de forma estrita e sem saltos a fase seguinte (Índice Atual + 1)
      final FaseModel faseSeguinte = fases[indiceAtual + 1];

      // 1. Registar a nova transição temporal no histórico de produção (Auditoria temporal)
      final historicoResponse = await _supabase.from('historico_producao').insert({
        'encomenda_id': encomenda.id,
        'fase_concluida_id': faseSeguinte.id,
        'utilizador_id': operadorId,
        'data_conclusao': DateTime.now().toIso8601String(),
      }).select().single();

      final int novoHistoricoId = historicoResponse['id'] as int;

      // 2. Atualizar o ponteiro de estado na tabela de encomendas
      await _supabase
          .from('encomendas')
          .update({'fase_atual_id': faseSeguinte.id})
          .eq('id', encomenda.id);

      print('⚙️ [Máquina de Estados] Encomenda ${encomenda.id} movida com sucesso para: ${faseSeguinte.nomeFasePadrao}');
    } catch (e) {
      print('❌ Erro na transição de estado (avancarFase): $e');
      rethrow;
    }
  }

  // =========================================================================
  // BLOCO 4: CONTROLO DE PARAGENS (Incidências)
  // =========================================================================

  /// Sinaliza um bloqueio operacional na estação de trabalho atual.
  Future<void> registarBloqueioComIncidencia({
    required int encomendaId,
    required int faseAtualId,
    required String motivo,
  }) async {
    try {
      // 1. Localizar o ID do histórico correspondente à fase ativa onde ocorreu o problema
      final historicoData = await _supabase
          .from('historico_producao')
          .select('id')
          .eq('encomenda_id', encomendaId)
          .eq('fase_concluida_id', faseAtualId)
          .order('data_conclusao', ascending: false)
          .limit(1)
          .single();

      final int historicoId = historicoData['id'] as int;

      // 2. Inserir a incidência vinculada a esse momento do fluxo
      await _supabase.from('incidencias').insert({
        'motivo': motivo.trim(),
        'data_registo': DateTime.now().toIso8601String(),
        'historico_producao_id': historicoId,
      });

      print('⚠️ [ALERTA MES] Encomenda $encomendaId marcada como BLOQUEADA. Motivo: $motivo');
    } catch (e) {
      print('❌ Erro ao registar paragem (registarBloqueioComIncidencia): $e');
      throw Exception('Falha ao registar a incidência na base de dados.');
    }
  }
}