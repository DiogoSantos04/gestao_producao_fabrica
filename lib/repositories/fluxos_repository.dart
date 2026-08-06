import '../models/fase_model.dart';
import 'base_repository.dart';

/// Engenharia de produto: tipologias e o respetivo roteiro de fabrico.
class FluxosRepository extends BaseRepository {
  // --- TIPOLOGIAS ---

  Future<List<Map<String, dynamic>>> obterTipologias() {
    return guarda('carregar as tipologias', () async {
      final dados = await client
          .from('tipos_produto')
          .select()
          .order('nome_tipo_produto', ascending: true);
      return comoLista(dados);
    });
  }

  /// Versão reduzida para dropdowns.
  Future<List<Map<String, dynamic>>> obterTipologiasParaSelecao() {
    return guarda('carregar os tipos de produto', () async {
      final dados = await client
          .from('tipos_produto')
          .select('id, nome_tipo_produto')
          .order('nome_tipo_produto');
      return comoLista(dados);
    });
  }

  Future<Map<String, dynamic>> criarTipologia(String nome) {
    return guarda('criar a tipologia', () async {
      final res = await client
          .from('tipos_produto')
          .insert({'nome_tipo_produto': nome.trim()})
          .select()
          .single();
      return Map<String, dynamic>.from(res);
    });
  }

  Future<void> eliminarTipologia(int id) {
    return guarda('eliminar a tipologia', () async {
      await client.from('tipos_produto').delete().eq('id', id);
    });
  }

  // --- FASES DO ROTEIRO ---

  Future<List<FaseModel>> obterFases(int tipoProdutoId) {
    return guarda('carregar as fases', () async {
      final dados = await client
          .from('fases_padrao')
          .select()
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem', ascending: true);
      return comoLista(dados).map(FaseModel.fromJson).toList();
    });
  }

  /// Todas as fases, agrupadas por tipo de produto — usado para calcular progresso.
  Future<Map<int, List<FaseModel>>> obterFasesPorProduto() {
    return guarda('carregar os roteiros de produção', () async {
      final dados = await client
          .from('fases_padrao')
          .select('id, ordem, tipos_produto_id, nome_fase_padrao, posto_trabalho, posto_trabalho_id')
          .order('ordem');

      final agrupadas = <int, List<FaseModel>>{};
      for (final f in comoLista(dados).map(FaseModel.fromJson)) {
        final prodId = f.tipoProdutoId;
        if (prodId != null) {
          agrupadas.putIfAbsent(prodId, () => []).add(f);
        }
      }
      return agrupadas;
    });
  }

  /// Fases de um produto para pré-visualização (nome, ordem, tempo, posto).
  ///
  /// A projeção não traz `id`, pelo que o [FaseModel] não é aplicável aqui.
  Future<List<Map<String, dynamic>>> obterFasesParaPreview(int tipoProdutoId) {
    return guarda('gerar a pré-visualização', () async {
      final dados = await client
          .from('fases_padrao')
          .select('nome_fase_padrao, ordem, tempo_estimado, posto_trabalho')
          .eq('tipos_produto_id', tipoProdutoId)
          .order('ordem');
      return comoLista(dados);
    });
  }

  /// Traduz cada fase no posto físico que a executa: `fase_id -> posto_id`.
  ///
  /// Só usa a coluna `posto_trabalho_id`. A coluna de texto `posto_trabalho` é
  /// legada e não é fiável como chave: na fábrica atual há fases cujo texto
  /// ("Posto de Controlo de Qualidade") não coincide com nenhum `nome_posto`
  /// ("Controlo de Qualidade"), pelo que casá-las por nome inventaria postos
  /// que não existem. Fases sem ligação ficam simplesmente de fora do mapa.
  Future<Map<int, int>> obterPostoPorFase() {
    return guarda('mapear as fases aos postos de trabalho', () async {
      final dados = await client
          .from('fases_padrao')
          .select('id, posto_trabalho_id')
          .not('posto_trabalho_id', 'is', null);

      return {
        for (final f in comoLista(dados))
          (f['id'] as num).toInt(): (f['posto_trabalho_id'] as num).toInt(),
      };
    });
  }

  /// Identificação mínima das fases, para mapear o fim de linha de cada produto.
  Future<List<Map<String, dynamic>>> obterFasesParaMapeamento() {
    return guarda('carregar o mapa de fases', () async {
      final dados = await client.from('fases_padrao').select('id, ordem, tipos_produto_id');
      return comoLista(dados);
    });
  }

  /// Primeira fase do roteiro de um produto, ou `null` se não houver roteiro.
  Future<Map<String, dynamic>?> obterFaseInicial(int tipoProdutoId) {
    return guarda('procurar a fase inicial', () async {
      // Pode existir mais do que uma fase com ordem 1 (dados legados/duplicados),
      // por isso limitamos em vez de exigir uma linha única.
      final res = await client
          .from('fases_padrao')
          .select('id')
          .eq('tipos_produto_id', tipoProdutoId)
          .eq('ordem', 1)
          .order('id')
          .limit(1);
      return res.isEmpty ? null : Map<String, dynamic>.from(res.first);
    });
  }

  Future<void> guardarFase({
    int? id,
    required int tipoProdutoId,
    required String nome,
    required String descricao,
    required String posto,
    required int tempo,
    required List<String> checklist,
    int? ordem,
  }) {
    return guarda('guardar a fase', () async {
      final dados = <String, dynamic>{
        'tipos_produto_id': tipoProdutoId,
        'nome_fase_padrao': nome,
        'descricao': descricao,
        'posto_trabalho': posto,
        'tempo_estimado': tempo,
        'checklist': checklist,
        'ordem': ordem,
      };
      dados.removeWhere((_, v) => v == null);

      if (id == null) {
        await client.from('fases_padrao').insert(dados);
      } else {
        await client.from('fases_padrao').update(dados).eq('id', id);
      }
    });
  }

  Future<void> eliminarFase(int id) {
    return guarda('eliminar a fase', () async {
      await client.from('fases_padrao').delete().eq('id', id);
    });
  }

  /// Clona o roteiro completo de uma tipologia para outra.
  Future<void> duplicarFases({
    required int novoTipoProdutoId,
    required List<FaseModel> fasesOrigem,
  }) {
    return guarda('duplicar o fluxo produtivo', () async {
      if (fasesOrigem.isEmpty) return;
      final payload = fasesOrigem
          .map((fase) => {
                'tipos_produto_id': novoTipoProdutoId,
                'nome_fase_padrao': fase.nomeFasePadrao,
                'descricao': fase.descricao,
                'posto_trabalho': fase.postoTrabalho,
                'posto_trabalho_id': fase.postoTrabalhoId,
                'tempo_estimado': fase.tempoEstimado,
                'checklist': fase.checklist,
                'ordem': fase.ordem,
              })
          .toList();
      await client.from('fases_padrao').insert(payload);
    });
  }

  /// Reescreve a coluna `ordem` de acordo com a sequência recebida.
  Future<void> reordenarFases(List<int> idsPorOrdem) {
    return guarda('guardar a nova ordenação', () async {
      for (int i = 0; i < idsPorOrdem.length; i++) {
        await client.from('fases_padrao').update({'ordem': i + 1}).eq('id', idsPorOrdem[i]);
      }
    });
  }
}
