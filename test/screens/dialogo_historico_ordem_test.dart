import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/checklist_model.dart';
import 'package:gestao_producao_fabrica/models/historico_model.dart';
import 'package:gestao_producao_fabrica/repositories/encomendas_repository.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/dialogos/dialogo_historico_ordem.dart';

HistoricoModel _fase(int id) => HistoricoModel.fromJson({
      'id': id,
      'encomenda_id': 42,
      'data_conclusao': '2026-08-06T10:00:00Z',
    });

RegistoConformidade _ponto(int historico, String item, {bool conforme = true}) =>
    RegistoConformidade.fromJson({
      'id': historico * 10,
      'historico_producao_id': historico,
      'encomenda_id': 42,
      'item': item,
      'conforme': conforme,
      'marcado_em': '2026-08-06T09:59:00Z',
    });

void main() {
  group('construirEventosTimeline — conformidade Poka-Yoke', () {
    test('os pontos validados ficam colados à fase que fecharam', () {
      final eventos = construirEventosTimeline(TimelineOrdem(
        producao: [_fase(1), _fase(2)],
        incidencias: const [],
        conformidade: {
          1: [_ponto(1, 'Verificar solda'), _ponto(1, 'Medir cota')],
        },
      ));

      final daFase1 =
          eventos.firstWhere((e) => e['timestamp'] != null && e['tipo'] == 'PRODUCAO');

      expect((daFase1['conformidade'] as List).length, 2);

      // A segunda fase não tem checklist: lista vazia, não os pontos da outra.
      final vazias = eventos
          .where((e) => (e['conformidade'] as List).isEmpty)
          .length;
      expect(vazias, 1);
    });

    test('lista vazia continua a ser List<RegistoConformidade>', () {
      // Um `const []` sem argumento de tipo dava `List<dynamic>` e rebentava no
      // cast do widget — precisamente no caso comum, a fase sem checklist.
      final eventos = construirEventosTimeline(TimelineOrdem(
        producao: [_fase(1)],
        incidencias: const [],
      ));

      expect(eventos.single['conformidade'], isA<List<RegistoConformidade>>());
    });

    test('timeline nula não gera eventos', () {
      expect(construirEventosTimeline(null), isEmpty);
    });

    test('desvio administrativo chega marcado como não conforme', () {
      final eventos = construirEventosTimeline(TimelineOrdem(
        producao: [_fase(1)],
        incidencias: const [],
        conformidade: {
          1: [
            _ponto(1, 'Avanço administrativo sem validação da checklist',
                conforme: false),
          ],
        },
      ));

      final pontos =
          eventos.single['conformidade'] as List<RegistoConformidade>;
      expect(pontos.single.conforme, isFalse);
    });
  });
}
