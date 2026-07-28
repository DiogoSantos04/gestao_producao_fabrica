import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/incidencia_model.dart';

void main() {
  group('IncidenciaModel.fromJson — campos nulos', () {
    test('só com id: todo o fluxo de manutenção fica no estado inicial', () {
      final i = IncidenciaModel.fromJson({'id': 1});

      expect(i.id, 1);
      expect(i.createdAt, isNull);
      expect(i.motivo, isNull);
      expect(i.dataRegisto, isNull);
      expect(i.encomendaId, isNull);
      expect(i.historicoProducaoId, isNull);
      expect(i.postoTrabalhoId, isNull);
      expect(i.reasonCodeId, isNull);
      expect(i.descricaoOperador, isNull);
      expect(i.estado, 'EM_ABERTO');
      expect(i.tipoManutencao, isNull);
      expect(i.tecnicoId, isNull);
      expect(i.entidadeExterna, isNull);
      expect(i.notaTecnica, isNull);
      expect(i.manutencaoConcluida, isFalse);
      expect(i.dataFimManutencao, isNull);
      expect(i.lineClearanceValidado, isFalse);
      expect(i.lineClearancePor, isNull);
      expect(i.dataLineClearance, isNull);
      expect(i.nomeTecnico, isNull);
      expect(i.categoriaReasonCode, isNull);
      expect(i.descricaoReasonCode, isNull);
    });

    test('estado nulo cai em EM_ABERTO — a linha fica bloqueada, não livre', () {
      expect(IncidenciaModel.fromJson({'id': 1, 'estado': null}).estado, 'EM_ABERTO');
    });

    test('os booleanos só são verdadeiros com true explícito', () {
      final nulos = IncidenciaModel.fromJson({
        'id': 1,
        'manutencao_concluida': null,
        'line_clearance_validado': null,
      });
      expect(nulos.manutencaoConcluida, isFalse);
      expect(nulos.lineClearanceValidado, isFalse);

      final texto = IncidenciaModel.fromJson({
        'id': 1,
        'line_clearance_validado': 'true',
      });
      expect(texto.lineClearanceValidado, isFalse);
    });

    test('datas inválidas ficam nulas', () {
      final i = IncidenciaModel.fromJson({
        'id': 1,
        'data_registo': 'ontem',
        'data_fim_manutencao': '',
        'data_line_clearance': null,
      });

      expect(i.dataRegisto, isNull);
      expect(i.dataFimManutencao, isNull);
      expect(i.dataLineClearance, isNull);
    });
  });

  group('IncidenciaModel — junções', () {
    test('técnico e reason code embebidos', () {
      final i = IncidenciaModel.fromJson({
        'id': 1,
        'utilizadores': {'nome_utilizador': 'Rui Alves'},
        'reason_codes': {'categoria': 'Mecânica', 'descricao': 'Avaria no motor'},
      });

      expect(i.nomeTecnico, 'Rui Alves');
      expect(i.categoriaReasonCode, 'Mecânica');
      expect(i.descricaoReasonCode, 'Avaria no motor');
    });

    test('junção como lista de um elemento é desembrulhada', () {
      final i = IncidenciaModel.fromJson({
        'id': 1,
        'utilizadores': [
          {'nome_utilizador': 'Rui Alves'},
        ],
      });
      expect(i.nomeTecnico, 'Rui Alves');
    });

    test('junção nula ou lista vazia deixa os campos nulos', () {
      final i = IncidenciaModel.fromJson({
        'id': 1,
        'utilizadores': [],
        'reason_codes': null,
      });
      expect(i.nomeTecnico, isNull);
      expect(i.categoriaReasonCode, isNull);
    });
  });

  group('IncidenciaModel — ciclo de vida', () {
    IncidenciaModel com({bool manutencaoConcluida = false, bool clearance = false}) =>
        IncidenciaModel.fromJson({
          'id': 1,
          'manutencao_concluida': manutencaoConcluida,
          'line_clearance_validado': clearance,
        });

    test('recém-registada: aberta e sem aguardar clearance', () {
      final i = com();
      expect(i.estaAberta, isTrue);
      expect(i.aguardaLineClearance, isFalse);
    });

    test('reparada mas sem clearance: continua aberta e aguarda validação', () {
      final i = com(manutencaoConcluida: true);
      expect(i.estaAberta, isTrue);
      expect(i.aguardaLineClearance, isTrue);
    });

    test('com clearance: fechada', () {
      final i = com(manutencaoConcluida: true, clearance: true);
      expect(i.estaAberta, isFalse);
      expect(i.aguardaLineClearance, isFalse);
    });

    test('clearance sem manutenção concluída fecha à mesma', () {
      // O clearance é a decisão final da qualidade e prevalece.
      final i = com(clearance: true);
      expect(i.estaAberta, isFalse);
      expect(i.aguardaLineClearance, isFalse);
    });
  });

  group('IncidenciaModel — campos derivados', () {
    test('inicio prefere data_registo e recorre ao created_at', () {
      final comRegisto = IncidenciaModel.fromJson({
        'id': 1,
        'created_at': '2026-02-01T08:00:00',
        'data_registo': '2026-02-01T10:00:00',
      });
      expect(comRegisto.inicio, DateTime(2026, 2, 1, 10));

      final semRegisto = IncidenciaModel.fromJson({
        'id': 1,
        'created_at': '2026-02-01T08:00:00',
      });
      expect(semRegisto.inicio, DateTime(2026, 2, 1, 8));

      expect(IncidenciaModel.fromJson({'id': 1}).inicio, isNull);
    });

    test('responsavelIntervencao prefere o técnico interno', () {
      final interno = IncidenciaModel.fromJson({
        'id': 1,
        'entidade_externa': 'AssistTec Lda',
        'utilizadores': {'nome_utilizador': 'Rui Alves'},
      });
      expect(interno.responsavelIntervencao, 'Rui Alves');

      final externo = IncidenciaModel.fromJson({
        'id': 1,
        'entidade_externa': 'AssistTec Lda',
      });
      expect(externo.responsavelIntervencao, 'AssistTec Lda');

      expect(IncidenciaModel.fromJson({'id': 1}).responsavelIntervencao, isNull);
    });
  });
}
