import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/encomenda_model.dart';
import 'package:gestao_producao_fabrica/models/fase_model.dart';
import 'package:gestao_producao_fabrica/models/historico_model.dart';
import 'package:gestao_producao_fabrica/models/incidencia_model.dart';
import 'package:gestao_producao_fabrica/repositories/operador_repository.dart';
import 'package:gestao_producao_fabrica/services/relatorio_turno.dart';

/// Registo de histórico mínimo, identificado por [id], da encomenda [encomenda],
/// concluído em [momento].
HistoricoModel _historico(int id, int encomenda, String momento) {
  return HistoricoModel.fromJson({
    'id': id,
    'encomenda_id': encomenda,
    'data_conclusao': momento,
  });
}

/// Paragem registada contra [encomenda] no instante [registo].
IncidenciaModel _paragem(int id, int? encomenda, String? registo) {
  return IncidenciaModel.fromJson({
    'id': id,
    'encomenda_id': encomenda,
    'data_registo': registo,
  });
}

void main() {
  group('OperadorRepository.progressoNoRoteiro', () {
    test('sem fase atual a ordem percorreu o roteiro todo', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20, 30],
          faseAtualId: null,
        ),
        1.0,
      );
    });

    test('primeira fase de um roteiro de 4 está a 0%', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20, 30, 40],
          faseAtualId: 10,
        ),
        0.0,
      );
    });

    test('terceira fase de um roteiro de 4 está a 50%', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20, 30, 40],
          faseAtualId: 30,
        ),
        0.5,
      );
    });

    test('a última fase ainda não está a 100% — falta concluí-la', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20, 30, 40],
          faseAtualId: 40,
        ),
        0.75,
      );
    });

    test('usa a posição e não a coluna ordem: numeração com saltos não engana', () {
      // Era exatamente aqui que `(ordem - 1) / total` falhava: com uma fase
      // removida do plano, a coluna `ordem` deixa de ser contígua e o cálculo
      // antigo passava de 100%.
      final roteiro = [7, 19, 44]; // ordens 1, 3 e 7 na base de dados
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: roteiro,
          faseAtualId: 44,
        ),
        closeTo(2 / 3, 1e-9),
      );
    });

    test('roteiro por carregar devolve 0.0, não uma divisão por zero', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [],
          faseAtualId: 10,
        ),
        0.0,
      );
    });

    test('fase que não pertence ao roteiro devolve 0.0 em vez de mentir', () {
      expect(
        OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20],
          faseAtualId: 99,
        ),
        0.0,
      );
    });

    test('o resultado nunca sai do intervalo [0, 1]', () {
      for (final fase in [10, 20, 30, 99, null]) {
        final p = OperadorRepository.progressoNoRoteiro(
          roteiro: const [10, 20, 30],
          faseAtualId: fase,
        );
        expect(p, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('OperadorRepository.associarParagens', () {
    test('a paragem fica na fase concluída logo a seguir ao registo', () {
      final historico = [
        _historico(1, 100, '2026-07-05T14:00:00Z'),
        _historico(2, 100, '2026-07-05T17:30:00Z'),
        _historico(3, 100, '2026-07-06T09:00:00Z'),
      ];
      final paragens = [_paragem(500, 100, '2026-07-05T16:10:00Z')];

      final resultado =
          OperadorRepository.associarParagens(historico, paragens);

      // Só a fase que estava a decorrer às 16:10 — a que fechou às 17:30.
      expect(resultado.keys, [2]);
      expect(resultado[2]!.single.id, 500);
    });

    test('não mancha as outras fases da mesma encomenda', () {
      final historico = [
        _historico(1, 100, '2026-07-05T14:00:00Z'),
        _historico(2, 100, '2026-07-05T17:30:00Z'),
      ];
      final paragens = [_paragem(500, 100, '2026-07-05T16:10:00Z')];

      final resultado =
          OperadorRepository.associarParagens(historico, paragens);

      expect(resultado.containsKey(1), isFalse);
    });

    test('a ordem de chegada do histórico não altera o resultado', () {
      // A query pode devolver por data descendente; a associação ordena por si.
      final historico = [
        _historico(3, 100, '2026-07-06T09:00:00Z'),
        _historico(2, 100, '2026-07-05T17:30:00Z'),
        _historico(1, 100, '2026-07-05T14:00:00Z'),
      ];
      final paragens = [_paragem(500, 100, '2026-07-05T16:10:00Z')];

      expect(
        OperadorRepository.associarParagens(historico, paragens).keys,
        [2],
      );
    });

    test('paragens de encomendas diferentes não se cruzam', () {
      final historico = [
        _historico(1, 100, '2026-07-05T17:00:00Z'),
        _historico(2, 200, '2026-07-05T18:00:00Z'),
      ];
      final paragens = [
        _paragem(500, 100, '2026-07-05T16:00:00Z'),
        _paragem(501, 200, '2026-07-05T16:30:00Z'),
      ];

      final resultado =
          OperadorRepository.associarParagens(historico, paragens);

      expect(resultado[1]!.single.id, 500);
      expect(resultado[2]!.single.id, 501);
    });

    test('várias paragens na mesma fase ficam todas', () {
      final historico = [_historico(1, 100, '2026-07-05T18:00:00Z')];
      final paragens = [
        _paragem(500, 100, '2026-07-05T15:00:00Z'),
        _paragem(501, 100, '2026-07-05T16:00:00Z'),
      ];

      final resultado =
          OperadorRepository.associarParagens(historico, paragens);

      expect(resultado[1]!.map((p) => p.id), [500, 501]);
    });

    test('paragem numa fase ainda a decorrer não aparece no histórico', () {
      // O histórico lista fases concluídas; esta ainda está aberta.
      final historico = [_historico(1, 100, '2026-07-05T14:00:00Z')];
      final paragens = [_paragem(500, 100, '2026-07-05T16:00:00Z')];

      expect(
        OperadorRepository.associarParagens(historico, paragens),
        isEmpty,
      );
    });

    test('paragem registada no instante exato da conclusão conta para essa fase', () {
      final historico = [_historico(1, 100, '2026-07-05T14:00:00Z')];
      final paragens = [_paragem(500, 100, '2026-07-05T14:00:00Z')];

      expect(
        OperadorRepository.associarParagens(historico, paragens).keys,
        [1],
      );
    });

    test('paragens sem encomenda ou sem data são ignoradas, não rebentam', () {
      final historico = [_historico(1, 100, '2026-07-05T18:00:00Z')];
      final paragens = [
        _paragem(500, null, '2026-07-05T15:00:00Z'),
        _paragem(501, 100, null),
      ];

      expect(
        OperadorRepository.associarParagens(historico, paragens),
        isEmpty,
      );
    });

    test('sem paragens nenhuma fase fica marcada', () {
      final historico = [_historico(1, 100, '2026-07-05T18:00:00Z')];
      expect(OperadorRepository.associarParagens(historico, const []), isEmpty);
    });
  });

  group('RegistoDeTurno', () {
    test('sem paragens não está bloqueado e não tem motivos', () {
      final r = RegistoDeTurno(registo: _historico(1, 100, '2026-07-05T18:00:00Z'));
      expect(r.bloqueado, isFalse);
      expect(r.motivos, isEmpty);
    });

    test('motivos repetidos aparecem uma só vez', () {
      final r = RegistoDeTurno(
        registo: _historico(1, 100, '2026-07-05T18:00:00Z'),
        paragens: [
          IncidenciaModel.fromJson({'id': 1, 'motivo': 'Avaria'}),
          IncidenciaModel.fromJson({'id': 2, 'motivo': 'Avaria'}),
          IncidenciaModel.fromJson({'id': 3, 'motivo': 'Falta de material'}),
        ],
      );

      expect(r.bloqueado, isTrue);
      expect(r.motivos, ['Avaria', 'Falta de material']);
    });

    test('sem motivo em texto livre recorre ao reason code', () {
      // É o caso normal desde o bug (D): a RPC grava `reason_code_id` e a
      // coluna `motivo` fica vazia.
      final r = RegistoDeTurno(
        registo: _historico(1, 100, '2026-07-05T18:00:00Z'),
        paragens: [
          IncidenciaModel.fromJson({
            'id': 1,
            'reason_codes': {'categoria': 'Manutenção', 'descricao': 'Avaria mecânica'},
          }),
        ],
      );

      expect(r.motivos, ['Avaria mecânica']);
    });

    test('paragem sem motivo nenhum não produz uma entrada vazia', () {
      final r = RegistoDeTurno(
        registo: _historico(1, 100, '2026-07-05T18:00:00Z'),
        paragens: [IncidenciaModel.fromJson({'id': 1, 'motivo': '   '})],
      );

      expect(r.bloqueado, isTrue, reason: 'a paragem existe');
      expect(r.motivos, isEmpty, reason: 'mas não há texto a mostrar');
    });
  });

  group('DetalheTarefa.faseAtual', () {
    /// Ordem na fase [faseAtualId], com um roteiro de três fases (10, 20, 30).
    DetalheTarefa detalhe({required int? faseAtualId, bool emSuspenso = false}) {
      return DetalheTarefa(
        encomenda: EncomendaModel.fromJson({
          'id': 1,
          'fase_atual_id': faseAtualId,
          'em_suspenso': emSuspenso,
        }),
        fases: [
          FaseModel.fromJson({'id': 10, 'nome_fase_padrao': 'Corte', 'ordem': 1}),
          FaseModel.fromJson({'id': 20, 'nome_fase_padrao': 'Soldadura', 'ordem': 2}),
          FaseModel.fromJson({'id': 30, 'nome_fase_padrao': 'Pintura', 'ordem': 3}),
        ],
        incidencias: const [],
      );
    }

    test('devolve a fase correspondente ao fase_atual_id', () {
      expect(detalhe(faseAtualId: 20).faseAtual?.nomeFasePadrao, 'Soldadura');
    });

    test('ordem concluída não tem fase atual nem é anómala', () {
      final d = detalhe(faseAtualId: null);
      expect(d.faseAtual, isNull);
      expect(d.faseForaDoRoteiro, isFalse);
    });

    test('fase fora do roteiro devolve null — não recua para a primeira', () {
      // Era aqui que o ecrã mentia: devolvia `fases.first`, e a confirmação de
      // conclusão apresentava "Corte" quando a ordem estava noutra fase.
      final d = detalhe(faseAtualId: 99);
      expect(d.faseAtual, isNull);
      expect(d.faseForaDoRoteiro, isTrue);
    });

    test('roteiro vazio com fase atual conta como fase fora do roteiro', () {
      final d = DetalheTarefa(
        encomenda: EncomendaModel.fromJson({'id': 1, 'fase_atual_id': 10}),
        fases: const [],
        incidencias: const [],
      );
      expect(d.faseAtual, isNull);
      expect(d.faseForaDoRoteiro, isTrue);
    });
  });

  group('DetalheTarefa.bloqueada', () {
    DetalheTarefa comIncidencias(
      List<Map<String, dynamic>> incidencias, {
      bool emSuspenso = false,
    }) {
      return DetalheTarefa(
        encomenda: EncomendaModel.fromJson({
          'id': 1,
          'fase_atual_id': 10,
          'em_suspenso': emSuspenso,
        }),
        fases: const [],
        incidencias: incidencias.map(IncidenciaModel.fromJson).toList(),
      );
    }

    test('ordem limpa não está bloqueada', () {
      expect(comIncidencias(const []).bloqueada, isFalse);
    });

    test('em_suspenso bloqueia mesmo sem incidências carregadas', () {
      expect(comIncidencias(const [], emSuspenso: true).bloqueada, isTrue);
    });

    test('incidência sem line clearance bloqueia mesmo sem em_suspenso', () {
      // Em regime normal andam juntas — a RPC escreve as duas —, mas uma
      // incidência aberta sozinha também tem de travar o posto.
      final d = comIncidencias([
        {'id': 1, 'line_clearance_validado': false},
      ]);
      expect(d.bloqueada, isTrue);
    });

    test('incidências todas validadas não bloqueiam', () {
      final d = comIncidencias([
        {'id': 1, 'line_clearance_validado': true},
        {'id': 2, 'line_clearance_validado': true},
      ]);
      expect(d.bloqueada, isFalse);
    });
  });

  group('OrdemNaFila.iniciada', () {
    OrdemNaFila ordem(Map<String, dynamic> extra) => OrdemNaFila(
          encomenda: EncomendaModel.fromJson({'id': 1, 'fase_atual_id': 30, ...extra}),
          // Duas fases já feitas noutros postos: a barra do roteiro não é zero.
          progresso: 0.5,
          fasesConcluidas: 2,
          totalFases: 4,
        );

    test('ordem acabada de chegar não está iniciada, mesmo com roteiro avançado', () {
      // O bug: "Em Progresso" vinha de `progresso > 0`, que conta as fases
      // feitas noutros postos.
      expect(ordem(const {}).iniciada, isFalse);
    });

    test('fica iniciada quando o servidor regista data_inicio_trabalho', () {
      expect(
        ordem({'data_inicio_trabalho': '2026-10-09T16:40:00Z'}).iniciada,
        isTrue,
      );
    });
  });

  group('DetalheTarefa.tempoParadoEntre', () {
    final inicio = DateTime.utc(2026, 10, 9, 10);
    final agora = DateTime.utc(2026, 10, 9, 12);

    DetalheTarefa comParagens(List<Map<String, dynamic>> paragens) {
      return DetalheTarefa(
        encomenda: EncomendaModel.fromJson({'id': 1, 'fase_atual_id': 10}),
        fases: const [],
        incidencias: paragens.map(IncidenciaModel.fromJson).toList(),
      );
    }

    test('paragem resolvida antes do início não é descontada', () {
      // Hold aplicado pelo admin com a ordem ainda em fila: não é tempo que o
      // cronómetro do operador tenha contado.
      final d = comParagens([
        {
          'id': 1,
          'data_registo': '2026-10-09T08:00:00Z',
          'line_clearance_validado': true,
          'data_line_clearance': '2026-10-09T09:00:00Z',
        },
      ]);
      expect(d.tempoParadoEntre(inicio, agora), Duration.zero);
    });

    test('paragem dentro do trabalho é descontada por inteiro', () {
      final d = comParagens([
        {
          'id': 1,
          'data_registo': '2026-10-09T10:30:00Z',
          'line_clearance_validado': true,
          'data_line_clearance': '2026-10-09T11:00:00Z',
        },
      ]);
      expect(d.tempoParadoEntre(inicio, agora), const Duration(minutes: 30));
    });

    test('paragem que atravessa o início só conta a parte depois dele', () {
      final d = comParagens([
        {
          'id': 1,
          'data_registo': '2026-10-09T09:30:00Z',
          'line_clearance_validado': true,
          'data_line_clearance': '2026-10-09T10:15:00Z',
        },
      ]);
      expect(d.tempoParadoEntre(inicio, agora), const Duration(minutes: 15));
    });

    test('paragem ainda aberta conta até agora', () {
      final d = comParagens([
        {'id': 1, 'data_registo': '2026-10-09T11:30:00Z'},
      ]);
      expect(d.tempoParadoEntre(inicio, agora), const Duration(minutes: 30));
    });
  });

  group('construirRelatorioTurno — incidências', () {
    IncidenciaModel registada(int id, String momento) => IncidenciaModel.fromJson({
          'id': id,
          'encomenda_id': 100,
          'data_registo': momento,
          'estado': 'PENDENTE',
          'reason_codes': {'categoria': 'Manutenção', 'descricao': 'Avaria mecânica'},
          'encomendas': {'codigo_rastreio': 'TRC-1'},
          'postos_trabalho': {'nome_posto': 'Corte'},
        });

    test('incidência em fase por concluir entra no relatório', () {
      // O bug: sem fase concluída depois da paragem — impossível em WIP Hold —
      // o relatório dava 0 alertas.
      final p = construirRelatorioTurno(
        nomeOperador: 'Op',
        dia: DateTime(2026, 10, 9),
        registos: const [],
        incidencias: [registada(48, '2026-10-09T16:46:00Z')],
      );

      expect(p.totalIncidencias, 1);
      expect(p.linhasIncidencias.single[1], 'TRC-1');
      expect(p.linhasIncidencias.single[2], 'Corte');
      expect(p.linhasIncidencias.single[3], 'Avaria mecânica');
      expect(p.linhasIncidencias.single[5], 'Pendente');
    });

    test('a mesma incidência pelas duas vias conta uma vez', () {
      final inc = registada(48, '2026-10-09T10:00:00Z');
      final p = construirRelatorioTurno(
        nomeOperador: 'Op',
        dia: DateTime(2026, 10, 9),
        registos: [
          RegistoDeTurno(
            registo: _historico(1, 100, '2026-10-09T12:00:00Z'),
            paragens: [inc],
          ),
        ],
        incidencias: [inc],
      );

      expect(p.totalIncidencias, 1);
    });

    test('incidência antiga sem autor continua a contar pela fase concluída', () {
      final p = construirRelatorioTurno(
        nomeOperador: 'Op',
        dia: DateTime(2026, 10, 9),
        registos: [
          RegistoDeTurno(
            registo: _historico(1, 100, '2026-10-09T12:00:00Z'),
            paragens: [_paragem(7, 100, '2026-10-09T11:00:00Z')],
          ),
        ],
      );

      expect(p.totalIncidencias, 1);
      expect(p.linhasIncidencias, isEmpty);
    });
  });

  group('OrdenacaoHistorico', () {
    test('só a data ordena por coluna própria; as outras por relação embebida', () {
      expect(OrdenacaoHistorico.data.alvo, ('data_conclusao', null));
      expect(OrdenacaoHistorico.codigo.alvo, ('codigo_rastreio', 'encomendas'));
      expect(OrdenacaoHistorico.fase.alvo, ('nome_fase_padrao', 'fases_padrao'));
    });
  });

  group('MetricasDoDia.apurar', () {
    /// Registo de turno concluído à hora local [hora] do dia 1 de junho.
    RegistoDeTurno registo(int id, int encomenda, String hora) {
      final local = DateTime(2026, 6, 1).add(Duration(
        hours: int.parse(hora.split(':')[0]),
        minutes: int.parse(hora.split(':')[1]),
      ));
      return RegistoDeTurno(
        registo: _historico(id, encomenda, local.toUtc().toIso8601String()),
      );
    }

    test('sem registos não afirma nada', () {
      final m = MetricasDoDia.apurar(const []);
      expect(m.primeira, isNull);
      expect(m.ultima, isNull);
      expect(m.intervaloMedio, isNull);
      expect(m.ordensDistintas, 0);
    });

    test('um só registo não tem intervalo para medir', () {
      final m = MetricasDoDia.apurar([registo(1, 10, '09:00')]);
      expect(m.intervaloMedio, isNull);
      expect(m.primeira, m.ultima);
      expect(m.ordensDistintas, 1);
    });

    test('média dos intervalos entre conclusões consecutivas', () {
      final m = MetricasDoDia.apurar([
        registo(1, 10, '09:00'),
        registo(2, 10, '09:20'),
        registo(3, 11, '09:50'),
      ]);
      // Intervalos de 20 e 30 minutos.
      expect(m.intervaloMedio, const Duration(minutes: 25));
      expect(m.intervalosIgnorados, 0);
      expect(m.ordensDistintas, 2);
    });

    test('a pausa de almoço não entra na média e é declarada', () {
      final m = MetricasDoDia.apurar([
        registo(1, 10, '09:00'),
        registo(2, 10, '09:30'),
        registo(3, 10, '14:00'), // 4h30 depois: pausa, não ritmo de trabalho
        registo(4, 10, '14:30'),
      ]);
      expect(m.intervaloMedio, const Duration(minutes: 30));
      expect(m.intervalosIgnorados, 1);
    });

    test('só pausas deixam a média por apurar em vez de a inventar', () {
      final m = MetricasDoDia.apurar([
        registo(1, 10, '08:00'),
        registo(2, 10, '18:00'),
      ]);
      expect(m.intervaloMedio, isNull);
      expect(m.intervalosIgnorados, 1);
    });

    test('a ordem de chegada dos registos não altera o apuramento', () {
      final m = MetricasDoDia.apurar([
        registo(3, 11, '09:50'),
        registo(1, 10, '09:00'),
        registo(2, 10, '09:20'),
      ]);
      expect(m.primeira!.hour, 9);
      expect(m.primeira!.minute, 0);
      expect(m.ultima!.minute, 50);
      expect(m.intervaloMedio, const Duration(minutes: 25));
    });
  });
}
