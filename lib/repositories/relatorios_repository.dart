import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/paginacao.dart';
import 'base_repository.dart';

/// Avaliações de clientes e o registo de auditoria dos relatórios emitidos.
class RelatoriosRepository extends BaseRepository {
  static const String _bucket = 'relatorios';

  /// Uma fatia das avaliações submetidas pelos clientes, mais recentes primeiro.
  Future<PaginaResultado<Map<String, dynamic>>> obterAvaliacoes({
    int deslocamento = 0,
    int tamanho = tamanhoPaginaPadrao,
  }) {
    return guarda('carregar as avaliações', () async {
      final dados = await client
          .from('avaliacoes')
          .select('nota, comentario, data_registo, encomendas(codigo_rastreio), clientes(nome_cliente)')
          .order('data_registo', ascending: false)
          // Uma linha a mais serve de sonda para saber se há mais avaliações.
          .range(deslocamento, deslocamento + tamanho);
      return PaginaResultado.aPartirDeSondagem(comoLista(dados), tamanho);
    });
  }

  /// Nota média de todas as avaliações, apurada sobre a tabela inteira.
  ///
  /// A média não pode sair da lista paginada — daria a média das avaliações que
  /// por acaso já estivessem no ecrã. Como o PostgREST não expõe `avg`, lê-se
  /// apenas a coluna `nota`: uma leitura de inteiros, sem as junções e os
  /// comentários que a lista precisa.
  Future<double> obterAvaliacaoMedia() {
    return guarda('calcular a avaliação média', () async {
      final notas = comoLista(await client.from('avaliacoes').select('nota'))
          .map((a) => (a['nota'] as num?)?.toDouble())
          .whereType<double>()
          .toList();
      if (notas.isEmpty) return 0.0;
      final media = notas.reduce((a, b) => a + b) / notas.length;
      return double.parse(media.toStringAsFixed(1));
    });
  }

  /// Histórico de relatórios emitidos (log de auditoria).
  Future<List<Map<String, dynamic>>> obterHistoricoEmissoes() {
    return guarda('carregar o histórico de relatórios', () async {
      final dados = await client
          .from('historico_relatorios')
          .select('*')
          .order('data_geracao', ascending: false);
      return comoLista(dados);
    });
  }

  /// Carrega o PDF para o storage e devolve a URL pública.
  Future<String> carregarPdf(Uint8List bytes) {
    return guarda('guardar o PDF na nuvem', () async {
      final nome = 'relatorio_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await client.storage.from(_bucket).uploadBinary(
            nome,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      return client.storage.from(_bucket).getPublicUrl(nome);
    });
  }

  /// Registo imutável de uma emissão de relatório.
  Future<void> registarEmissao({
    required String periodoInicio,
    required String periodoFim,
    required int totalConcluidas,
    required double taxaPrazo,
    required String urlPdf,
    required String geradoPor,
  }) {
    return guarda('registar a emissão do relatório', () async {
      await client.from('historico_relatorios').insert({
        'periodo_inicio': periodoInicio,
        'periodo_fim': periodoFim,
        'total_concluidas': totalConcluidas,
        'taxa_prazo': taxaPrazo,
        'url_pdf': urlPdf,
        'gerado_por': geradoPor,
      });
    });
  }
}
