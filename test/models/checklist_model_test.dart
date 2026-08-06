import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/checklist_model.dart';

void main() {
  group('PontoValidado.toJson — payload da RPC', () {
    test('leva posição, item e a hora da marcação em UTC', () {
      final ponto = PontoValidado(
        posicao: 2,
        item: 'Verificar aperto do parafuso',
        marcadoEm: DateTime.utc(2026, 8, 6, 14, 30),
      );

      expect(ponto.toJson(), {
        'posicao': 2,
        'item': 'Verificar aperto do parafuso',
        'conforme': true,
        'marcado_em': '2026-08-06T14:30:00.000Z',
      });
    });

    test('hora local é convertida — o servidor guarda timestamptz', () {
      final local = DateTime(2026, 8, 6, 9);
      final ponto = PontoValidado(posicao: 0, item: 'x', marcadoEm: local);

      expect(
        ponto.toJson()['marcado_em'],
        local.toUtc().toIso8601String(),
      );
    });

    test('conforme é sempre true: o ponto que falha não fecha a fase', () {
      final ponto = PontoValidado(
        posicao: 0,
        item: 'x',
        marcadoEm: DateTime.utc(2026),
      );

      expect(ponto.toJson()['conforme'], isTrue);
    });
  });

  group('RegistoConformidade.fromJson', () {
    test('linha completa, com o operador da junção', () {
      final r = RegistoConformidade.fromJson({
        'id': 7,
        'historico_producao_id': 55,
        'encomenda_id': 42,
        'fase_id': 9,
        'posicao': 1,
        'item': 'Medir cota',
        'conforme': true,
        'marcado_em': '2026-08-06T14:30:00Z',
        'utilizadores': {'nome_utilizador': 'Ana'},
      });

      expect(r.id, 7);
      expect(r.historicoProducaoId, 55);
      expect(r.encomendaId, 42);
      expect(r.faseId, 9);
      expect(r.posicao, 1);
      expect(r.item, 'Medir cota');
      expect(r.conforme, isTrue);
      expect(r.marcadoEm, DateTime.utc(2026, 8, 6, 14, 30));
      expect(r.nomeOperador, 'Ana');
    });

    test('só com id: nada é inventado', () {
      final r = RegistoConformidade.fromJson({'id': 1});

      expect(r.historicoProducaoId, isNull);
      expect(r.faseId, isNull);
      expect(r.marcadoEm, isNull);
      expect(r.nomeOperador, isNull);
      expect(r.item, '');
    });

    test('desvio administrativo chega marcado como não conforme', () {
      final r = RegistoConformidade.fromJson({
        'id': 2,
        'item': 'Avanço administrativo sem validação da checklist',
        'conforme': false,
      });

      expect(r.conforme, isFalse);
    });

    test('junção ausente não rebenta a leitura', () {
      final r = RegistoConformidade.fromJson({
        'id': 3,
        'item': 'Medir cota',
        'utilizadores': null,
      });

      expect(r.nomeOperador, isNull);
    });
  });
}
