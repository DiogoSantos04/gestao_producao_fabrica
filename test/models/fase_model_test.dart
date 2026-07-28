import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/fase_model.dart';

void main() {
  group('FaseModel.fromJson — campos nulos', () {
    test('só com id: nenhum dos campos antes obrigatórios rebenta', () {
      // A versão anterior exigia nome_fase_padrao, ordem e tipos_produto_id.
      final f = FaseModel.fromJson({'id': 1});

      expect(f.id, 1);
      expect(f.createdAt, isNull);
      expect(f.nomeFasePadrao, '');
      expect(f.ordem, 0);
      expect(f.tipoProdutoId, isNull);
      expect(f.descricao, isNull);
      expect(f.tempoEstimado, 0);
      expect(f.postoTrabalho, isNull);
      expect(f.postoTrabalhoId, isNull);
      expect(f.checklist, isEmpty);
    });

    test('nulos explícitos caem nos valores por omissão', () {
      final f = FaseModel.fromJson({
        'id': 1,
        'nome_fase_padrao': null,
        'ordem': null,
        'tempo_estimado': null,
        'checklist': null,
      });

      expect(f.nomeFasePadrao, '');
      expect(f.ordem, 0);
      expect(f.tempoEstimado, 0);
      expect(f.checklist, isEmpty);
    });

    test('campos completos', () {
      final f = FaseModel.fromJson({
        'id': 3,
        'created_at': '2026-01-10T09:00:00',
        'nome_fase_padrao': 'Montagem',
        'ordem': 2,
        'tipos_produto_id': 7,
        'descricao': 'Montagem final',
        'tempo_estimado': 45,
        'posto_trabalho': 'Bancada 2',
        'posto_trabalho_id': 11,
      });

      expect(f.nomeFasePadrao, 'Montagem');
      expect(f.ordem, 2);
      expect(f.tipoProdutoId, 7);
      expect(f.tempoEstimado, 45);
      expect(f.postoTrabalho, 'Bancada 2');
      expect(f.postoTrabalhoId, 11);
      expect(f.createdAt, DateTime(2026, 1, 10, 9));
    });

    test('created_at inválido fica nulo', () {
      expect(FaseModel.fromJson({'id': 1, 'created_at': 'ontem'}).createdAt, isNull);
    });

    test('a coluna legada posto_trabalho é independente do posto_trabalho_id', () {
      // Só o id é a ligação real; o texto é mantido por trigger e pode faltar.
      final f = FaseModel.fromJson({'id': 1, 'posto_trabalho_id': 4});
      expect(f.postoTrabalhoId, 4);
      expect(f.postoTrabalho, isNull);
    });
  });

  group('FaseModel.checklist', () {
    test('lista de strings', () {
      final f = FaseModel.fromJson({
        'id': 1,
        'checklist': ['Verificar torque', 'Limpar bancada'],
      });
      expect(f.checklist, ['Verificar torque', 'Limpar bancada']);
    });

    test('elementos não-texto são convertidos, não descartados', () {
      final f = FaseModel.fromJson({
        'id': 1,
        'checklist': [1, true],
      });
      expect(f.checklist, ['1', 'true']);
    });

    test('checklist que não é lista dá lista vazia', () {
      expect(FaseModel.fromJson({'id': 1, 'checklist': 'texto'}).checklist, isEmpty);
      expect(FaseModel.fromJson({'id': 1, 'checklist': []}).checklist, isEmpty);
    });
  });
}
