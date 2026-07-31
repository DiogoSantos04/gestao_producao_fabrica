import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/reason_code_model.dart';

void main() {
  group('ReasonCodeModel.fromJson', () {
    test('só com id: cai nos valores por omissão sem rebentar', () {
      final r = ReasonCodeModel.fromJson({'id': 3});

      expect(r.id, 3);
      expect(r.categoria, 'Geral');
      expect(r.descricao, '');
      expect(r.tempoEstimadoMinutos, isNull);
    });

    test('campos completos', () {
      final r = ReasonCodeModel.fromJson({
        'id': 7,
        'categoria': 'Manutenção',
        'descricao': 'Avaria mecânica',
        'tempo_estimado_minutos': 45,
      });

      expect(r.categoria, 'Manutenção');
      expect(r.descricao, 'Avaria mecânica');
      expect(r.tempoEstimadoMinutos, 45);
    });

    test('categoria vazia ou só espaços cai em Geral', () {
      expect(ReasonCodeModel.fromJson({'id': 1, 'categoria': ''}).categoria, 'Geral');
      expect(ReasonCodeModel.fromJson({'id': 1, 'categoria': '  '}).categoria, 'Geral');
    });

    test('espaços à volta são removidos', () {
      final r = ReasonCodeModel.fromJson({
        'id': 1,
        'categoria': '  Qualidade  ',
        'descricao': '  Não conformidade  ',
      });

      expect(r.categoria, 'Qualidade');
      expect(r.descricao, 'Não conformidade');
    });

    test('id aceita o double que o PostgREST pode devolver em web', () {
      expect(ReasonCodeModel.fromJson({'id': 4.0}).id, 4);
    });
  });

  group('ReasonCodeModel.rotulo', () {
    test('categoria e descrição', () {
      final r = ReasonCodeModel.fromJson({
        'id': 1,
        'categoria': 'Manutenção',
        'descricao': 'Avaria mecânica',
      });

      expect(r.rotulo, '[Manutenção] Avaria mecânica');
    });

    test('sem descrição não deixa um espaço pendurado no fim', () {
      final r = ReasonCodeModel.fromJson({'id': 1, 'categoria': 'Logística'});
      expect(r.rotulo, '[Logística]');
    });
  });
}
