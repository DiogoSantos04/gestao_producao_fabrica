import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'base_repository.dart';

/// Avaliações de clientes e o registo de auditoria dos relatórios emitidos.
class RelatoriosRepository extends BaseRepository {
  static const String _bucket = 'relatorios';

  /// Avaliações submetidas pelos clientes, mais recentes primeiro.
  Future<List<Map<String, dynamic>>> obterAvaliacoes() {
    return guarda('carregar as avaliações', () async {
      final dados = await client
          .from('avaliacoes')
          .select('nota, comentario, data_registo, encomendas(codigo_rastreio), clientes(nome_cliente)')
          .order('data_registo', ascending: false);
      return comoLista(dados);
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
