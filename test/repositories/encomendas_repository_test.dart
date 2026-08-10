import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/estado_ordem.dart';
import 'package:gestao_producao_fabrica/models/historico_model.dart';
import 'package:gestao_producao_fabrica/models/incidencia_model.dart';
import 'package:gestao_producao_fabrica/repositories/encomendas_repository.dart';

void main() {
  group('EncomendasRepository.condicoesDoFiltro', () {
    test('o filtro "todos" esconde as canceladas', () {
      // Sem esta condição, as ordens canceladas voltariam a aparecer no painel
      // misturadas com as ativas, que é precisamente o que a filtragem em
      // memória evitava antes de a paginação passar para o servidor.
      expect(
        EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.todos),
        const [CondicaoEstado.igual('cancelada', false)],
      );
    });

    test('canceladas é o único filtro que pede cancelada = true', () {
      expect(
        EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.cancelada),
        const [CondicaoEstado.igual('cancelada', true)],
      );
    });

    test('em hold: não cancelada e em suspenso', () {
      expect(
        EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.emHold),
        const [
          CondicaoEstado.igual('cancelada', false),
          CondicaoEstado.igual('em_suspenso', true),
        ],
      );
    });

    test('em produção: fora de hold e com fase atual', () {
      expect(
        EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.emProducao),
        const [
          CondicaoEstado.igual('cancelada', false),
          CondicaoEstado.igual('em_suspenso', false),
          CondicaoEstado.naoEhNulo('fase_atual_id'),
        ],
      );
    });

    test('concluída: fora de hold e sem fase atual', () {
      expect(
        EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.concluida),
        const [
          CondicaoEstado.igual('cancelada', false),
          CondicaoEstado.igual('em_suspenso', false),
          CondicaoEstado.ehNulo('fase_atual_id'),
        ],
      );
    });

    test('atrasada: na linha e com o prazo ultrapassado', () {
      // Não filtra por `em_suspenso`: uma ordem em hold com o prazo a arder
      // continua atrasada, e escondê-la seria esconder o pior caso.
      expect(
        EncomendasRepository.condicoesDoFiltro(
          FiltroEstadoOrdem.atrasada,
          hoje: DateTime(2026, 8, 6),
        ),
        const [
          CondicaoEstado.igual('cancelada', false),
          CondicaoEstado.naoEhNulo('fase_atual_id'),
          CondicaoEstado.menorQue('data_entrega', '2026-08-06'),
        ],
      );
    });

    test('atrasada compara com o dia, não com o instante', () {
      // `data_entrega` é uma `date`: passar um timestamp faria uma ordem que
      // entrega hoje aparecer como atrasada a partir do meio-dia.
      final condicoes = EncomendasRepository.condicoesDoFiltro(
        FiltroEstadoOrdem.atrasada,
        hoje: DateTime(2026, 8, 6, 23, 59),
      );

      expect(condicoes.last, const CondicaoEstado.menorQue('data_entrega', '2026-08-06'));
    });

    test('em produção e concluída são mutuamente exclusivos', () {
      // A mesma ordem não pode cair nos dois filtros: um exige fase atual, o
      // outro exige a ausência dela.
      final producao =
          EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.emProducao);
      final concluida =
          EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.concluida);

      expect(producao.contains(const CondicaoEstado.naoEhNulo('fase_atual_id')), isTrue);
      expect(concluida.contains(const CondicaoEstado.ehNulo('fase_atual_id')), isTrue);
    });

    test('em hold ganha a em produção: não exclui as ordens com fase atual', () {
      // Precedência de EstadoOrdem.derivar — uma ordem suspensa continua a ter
      // fase atual, e tem de aparecer em "em hold" e não em "em produção".
      final hold =
          EncomendasRepository.condicoesDoFiltro(FiltroEstadoOrdem.emHold);
      expect(hold.any((c) => c.coluna == 'fase_atual_id'), isFalse);
    });

    test('nenhum filtro além de canceladas mostra ordens canceladas', () {
      for (final f in FiltroEstadoOrdem.values) {
        if (f == FiltroEstadoOrdem.cancelada) continue;
        expect(
          EncomendasRepository.condicoesDoFiltro(f),
          contains(const CondicaoEstado.igual('cancelada', false)),
          reason: 'filtro $f',
        );
      }
    });
  });

  group('EncomendasRepository.termoPesquisa', () {
    test('pesquisa vazia devolve null — não filtra nada', () {
      expect(EncomendasRepository.termoPesquisa(''), isNull);
    });

    test('só espaços conta como pesquisa vazia', () {
      expect(EncomendasRepository.termoPesquisa('   '), isNull);
    });

    test('espaços à volta do termo são cortados', () {
      expect(EncomendasRepository.termoPesquisa('  ORD-42 '), 'ORD-42');
    });

    test('vírgulas, parênteses e aspas são removidos', () {
      // São a sintaxe do or() do PostgREST: deixá-los passar partia a query em
      // vez de procurar por eles.
      expect(
        EncomendasRepository.termoPesquisa('a,b(c)"d"'),
        'abcd',
      );
    });

    test('um termo feito só de sintaxe do PostgREST não vira pesquisa', () {
      expect(EncomendasRepository.termoPesquisa('(),"'), isNull);
    });

    test('espaços interiores e acentos são preservados', () {
      expect(
        EncomendasRepository.termoPesquisa('  Metalúrgica Sul  '),
        'Metalúrgica Sul',
      );
    });

    test('o caractere % do LIKE passa: é pesquisa do utilizador, não sintaxe do or()', () {
      expect(EncomendasRepository.termoPesquisa('50%'), '50%');
    });
  });

  group('TimelineOrdem', () {
    HistoricoModel historico() =>
        HistoricoModel.fromJson({'id': 1, 'encomenda_id': 100});
    IncidenciaModel incidencia() => IncidenciaModel.fromJson({'id': 1});

    test('sem produção nem incidências está vazia', () {
      expect(
        const TimelineOrdem(producao: [], incidencias: []).vazia,
        isTrue,
      );
    });

    test('só com produção não está vazia', () {
      expect(
        TimelineOrdem(producao: [historico()], incidencias: const []).vazia,
        isFalse,
      );
    });

    test('só com incidências não está vazia', () {
      // Uma ordem parada logo na primeira fase não tem histórico nenhum, mas a
      // timeline tem de mostrar a paragem.
      expect(
        TimelineOrdem(producao: const [], incidencias: [incidencia()]).vazia,
        isFalse,
      );
    });
  });

  group('EncomendasRepository.agregarPareto', () {
    final agora = DateTime(2026, 8, 6, 12, 0);

    IncidenciaModel paragem({
      int? reasonCodeId = 1,
      String? categoria = 'Mecânica',
      String? descricao = 'Rolamento partido',
      String? motivo,
      DateTime? inicio,
      DateTime? fimManutencao,
      DateTime? lineClearance,
    }) {
      return IncidenciaModel.fromJson({
        'id': 1,
        'reason_code_id': reasonCodeId,
        'motivo': motivo,
        'data_registo': (inicio ?? agora.subtract(const Duration(minutes: 30)))
            .toIso8601String(),
        'data_fim_manutencao': fimManutencao?.toIso8601String(),
        'data_line_clearance': lineClearance?.toIso8601String(),
        if (reasonCodeId != null)
          'reason_codes': {'categoria': categoria, 'descricao': descricao},
      });
    }

    test('agrupa pelo reason_code e conta as ocorrências', () {
      final resultado = EncomendasRepository.agregarPareto(
        [paragem(), paragem(), paragem(reasonCodeId: 2, descricao: 'Falta de material')],
        agora: agora,
      );

      expect(resultado.map((p) => p.rotulo), ['Rolamento partido', 'Falta de material']);
      expect(resultado.first.ocorrencias, 2);
    });

    test('por tempo perdido, o motivo raro e demorado passa à frente do frequente e rápido', () {
      // É o ponto do segundo critério: o motivo 1 acontece três vezes e custa
      // 30 minutos ao todo; o motivo 2 acontece uma vez e custa 120. Por
      // ocorrências ganha o primeiro, por tempo perdido ganha o segundo — e a
      // decisão de manutenção que cada leitura sugere é diferente.
      final rapidas = List.generate(
        3,
        (_) => paragem(
          inicio: agora.subtract(const Duration(minutes: 20)),
          fimManutencao: agora.subtract(const Duration(minutes: 10)),
        ),
      );
      final demorada = paragem(
        reasonCodeId: 2,
        descricao: 'Avaria mecânica',
        inicio: agora.subtract(const Duration(minutes: 200)),
        fimManutencao: agora.subtract(const Duration(minutes: 80)),
      );

      final porOcorrencias = EncomendasRepository.agregarPareto(
        [...rapidas, demorada],
        agora: agora,
      );
      final porTempo = EncomendasRepository.agregarPareto(
        [...rapidas, demorada],
        criterio: CriterioPareto.tempoPerdido,
        agora: agora,
      );

      expect(porOcorrencias.first.rotulo, 'Rolamento partido');
      expect(porTempo.first.rotulo, 'Avaria mecânica');
      expect(porTempo.first.minutosTotais, 120);
    });

    test('sem limite devolve todos os motivos, para a curva acumulada ter o total real', () {
      final resultado = EncomendasRepository.agregarPareto(
        List.generate(7, (i) => paragem(reasonCodeId: i + 1, descricao: 'Motivo $i')),
        agora: agora,
      );

      expect(resultado.length, 7);
    });

    test('com limite corta ao topo pedido', () {
      final resultado = EncomendasRepository.agregarPareto(
        List.generate(7, (i) => paragem(reasonCodeId: i + 1, descricao: 'Motivo $i')),
        limite: 5,
        agora: agora,
      );

      expect(resultado.length, 5);
    });

    test('o texto livre não cria motivos: duas frases do mesmo código contam juntas', () {
      // É o ponto todo da agregação por reason_code — ver bug (D). Com a coluna
      // `motivo` estas duas linhas seriam dois motivos distintos.
      final resultado = EncomendasRepository.agregarPareto(
        [
          paragem(motivo: 'partiu o rolamento'),
          paragem(motivo: 'rolamento foi abaixo outra vez'),
        ],
        agora: agora,
      );

      expect(resultado, hasLength(1));
      expect(resultado.single.ocorrencias, 2);
    });

    test('incidências sem reason_code são ignoradas', () {
      final resultado = EncomendasRepository.agregarPareto(
        [paragem(reasonCodeId: null, motivo: 'avariou')],
        agora: agora,
      );

      expect(resultado, isEmpty);
    });

    test('uma paragem fechada conta até ao line clearance', () {
      final resultado = EncomendasRepository.agregarPareto(
        [
          paragem(
            inicio: DateTime(2026, 8, 6, 9, 0),
            fimManutencao: DateTime(2026, 8, 6, 9, 30),
            lineClearance: DateTime(2026, 8, 6, 10, 0),
          ),
        ],
        agora: agora,
      );

      // 60 minutos e não 30: entre o fim da manutenção e o line clearance a
      // ordem continua bloqueada.
      expect(resultado.single.minutosTotais, 60);
    });

    test('uma paragem ainda aberta conta até agora', () {
      final resultado = EncomendasRepository.agregarPareto(
        [paragem(inicio: DateTime(2026, 8, 6, 10, 0))],
        agora: agora,
      );

      expect(resultado.single.minutosTotais, 120);
    });

    test('o limite corta os motivos menos frequentes', () {
      final resultado = EncomendasRepository.agregarPareto(
        [
          paragem(),
          paragem(),
          paragem(reasonCodeId: 2, descricao: 'B'),
          paragem(reasonCodeId: 3, descricao: 'C'),
        ],
        limite: 2,
        agora: agora,
      );

      expect(resultado, hasLength(2));
      expect(resultado.first.ocorrencias, 2);
    });

    test('empate desempata pelo rótulo, para a ordem não oscilar', () {
      final resultado = EncomendasRepository.agregarPareto(
        [
          paragem(reasonCodeId: 2, descricao: 'Zebra', inicio: agora),
          paragem(reasonCodeId: 3, descricao: 'Alfa', inicio: agora),
        ],
        agora: agora,
      );

      expect(resultado.map((p) => p.rotulo), ['Alfa', 'Zebra']);
    });

    test('sem descrição o rótulo cai na categoria', () {
      final resultado = EncomendasRepository.agregarPareto(
        [paragem(descricao: '')],
        agora: agora,
      );

      expect(resultado.single.rotulo, 'Mecânica');
    });

    test('minutosMedios divide o total pelas ocorrências', () {
      final resultado = EncomendasRepository.agregarPareto(
        [
          paragem(inicio: DateTime(2026, 8, 6, 11, 0)),
          paragem(inicio: DateTime(2026, 8, 6, 10, 0)),
        ],
        agora: agora,
      );

      expect(resultado.single.minutosTotais, 180);
      expect(resultado.single.minutosMedios, 90);
    });
  });

  group('EncomendasRepository.pertenceAoFiltro', () {
    final hoje = DateTime(2026, 8, 6, 14, 30);

    bool pertence(
      FiltroEstadoOrdem filtro, {
      bool cancelada = false,
      bool emSuspenso = false,
      bool temFaseAtual = true,
      DateTime? dataEntrega,
    }) {
      return EncomendasRepository.pertenceAoFiltro(
        filtro,
        cancelada: cancelada,
        emSuspenso: emSuspenso,
        temFaseAtual: temFaseAtual,
        dataEntrega: dataEntrega,
        hoje: hoje,
      );
    }

    test('todas aceita tudo menos as canceladas', () {
      expect(pertence(FiltroEstadoOrdem.todos), isTrue);
      expect(pertence(FiltroEstadoOrdem.todos, cancelada: true), isFalse);
    });

    test('em hold e em produção seguem EstadoOrdem.derivar', () {
      expect(pertence(FiltroEstadoOrdem.emHold, emSuspenso: true), isTrue);
      expect(pertence(FiltroEstadoOrdem.emHold), isFalse);
      expect(pertence(FiltroEstadoOrdem.emProducao), isTrue);
    });

    test('atrasada: prazo anterior a hoje', () {
      expect(
        pertence(FiltroEstadoOrdem.atrasada, dataEntrega: DateTime(2026, 8, 5)),
        isTrue,
      );
    });

    test('entregar hoje ainda não é estar atrasado', () {
      expect(
        pertence(FiltroEstadoOrdem.atrasada, dataEntrega: DateTime(2026, 8, 6)),
        isFalse,
      );
    });

    test('a hora do dia não antecipa o atraso', () {
      // Às 14:30 de hoje, uma ordem que entrega hoje às 00:00 continua no prazo.
      expect(
        pertence(FiltroEstadoOrdem.atrasada, dataEntrega: DateTime(2026, 8, 6, 0, 0)),
        isFalse,
      );
    });

    test('uma ordem em hold com o prazo expirado está atrasada', () {
      expect(
        pertence(FiltroEstadoOrdem.atrasada,
            emSuspenso: true, dataEntrega: DateTime(2026, 8, 1)),
        isTrue,
      );
    });

    test('concluída ou cancelada nunca aparece em atrasada', () {
      expect(
        pertence(FiltroEstadoOrdem.atrasada,
            temFaseAtual: false, dataEntrega: DateTime(2026, 8, 1)),
        isFalse,
      );
      expect(
        pertence(FiltroEstadoOrdem.atrasada,
            cancelada: true, dataEntrega: DateTime(2026, 8, 1)),
        isFalse,
      );
    });

    test('sem prazo não há atraso', () {
      expect(pertence(FiltroEstadoOrdem.atrasada), isFalse);
    });

    test('atrasada não cai no ramo de "todas"', () {
      // `FiltroEstadoOrdem.atrasada.estado` é null, tal como o de "todas": se a
      // decisão fosse tomada só pelo estado, o painel deixaria entrar por
      // realtime ordens que não estão atrasadas.
      expect(FiltroEstadoOrdem.atrasada.estado, isNull);
      expect(
        pertence(FiltroEstadoOrdem.atrasada, dataEntrega: DateTime(2026, 12, 1)),
        isFalse,
      );
    });
  });

  group('EncomendasRepository.contarConcluidasEm', () {
    final hoje = DateTime(2026, 8, 6, 15, 0);
    final ontem = DateTime(2026, 8, 5, 15, 0);

    test('conta a ordem no dia em que fechou a última fase', () {
      final conclusoes = {
        1: DateTime(2026, 8, 6, 9, 0),
        2: DateTime(2026, 8, 5, 17, 0),
      };

      expect(
        EncomendasRepository.contarConcluidasEm(hoje,
            idsConcluidas: {1, 2}, ultimasConclusoes: conclusoes),
        1,
      );
      expect(
        EncomendasRepository.contarConcluidasEm(ontem,
            idsConcluidas: {1, 2}, ultimasConclusoes: conclusoes),
        1,
      );
    });

    test('uma ordem que trabalhou ontem e fechou hoje só conta hoje', () {
      // É o erro que a regra antiga cometia: contava a ordem nos dois dias e
      // inflacionava o total de ontem, que é o número de comparação.
      final conclusoes = {1: DateTime(2026, 8, 6, 8, 0)};

      expect(
        EncomendasRepository.contarConcluidasEm(ontem,
            idsConcluidas: {1}, ultimasConclusoes: conclusoes),
        0,
      );
      expect(
        EncomendasRepository.contarConcluidasEm(hoje,
            idsConcluidas: {1}, ultimasConclusoes: conclusoes),
        1,
      );
    });

    test('ordens ainda em produção não contam, mesmo tendo fechado fases hoje', () {
      final conclusoes = {7: DateTime(2026, 8, 6, 10, 0)};

      expect(
        EncomendasRepository.contarConcluidasEm(hoje,
            idsConcluidas: const {}, ultimasConclusoes: conclusoes),
        0,
      );
    });

    test('uma ordem concluída sem histórico na janela não conta', () {
      expect(
        EncomendasRepository.contarConcluidasEm(hoje,
            idsConcluidas: {1}, ultimasConclusoes: const {}),
        0,
      );
    });

    test('uma conclusão em UTC conta no dia do calendário local', () {
      // `data_conclusao` é `timestamptz` e chega em UTC. Comparar o dia UTC com
      // o dia do relógio da fábrica punha o turno da noite no dia errado.
      // (Num ambiente com TZ=UTC os dois coincidem e o teste é tautológico; a
      // verificação real é a normalização estar cá.)
      final instante = DateTime.utc(2026, 8, 6, 23, 30);

      expect(
        EncomendasRepository.contarConcluidasEm(
          instante.toLocal(),
          idsConcluidas: {1},
          ultimasConclusoes: {1: instante},
        ),
        1,
      );
    });

    test('a hora não interessa, só o dia', () {
      final conclusoes = {1: DateTime(2026, 8, 6, 23, 59)};

      expect(
        EncomendasRepository.contarConcluidasEm(DateTime(2026, 8, 6, 0, 1),
            idsConcluidas: {1}, ultimasConclusoes: conclusoes),
        1,
      );
    });
  });

  group('EncomendasRepository.tempoMedioParagemAberta', () {
    final agora = DateTime(2026, 8, 6, 12, 0);

    IncidenciaModel aberta({
      DateTime? inicio,
      DateTime? createdAt,
      DateTime? fimManutencao,
    }) {
      return IncidenciaModel.fromJson({
        'id': 1,
        'data_registo': inicio?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'data_fim_manutencao': fimManutencao?.toIso8601String(),
      });
    }

    test('sem paragens devolve null, não zero', () {
      // "Sem paragens" e "paragens que começaram agora" são opostos; um 0 min
      // no ecrã não os distinguiria.
      expect(
        EncomendasRepository.tempoMedioParagemAberta(const [], agora: agora),
        isNull,
      );
    });

    test('faz a média dos minutos desde o início de cada paragem', () {
      final media = EncomendasRepository.tempoMedioParagemAberta(
        [
          aberta(inicio: DateTime(2026, 8, 6, 10, 0)),
          aberta(inicio: DateTime(2026, 8, 6, 11, 0)),
        ],
        agora: agora,
      );

      expect(media, const Duration(minutes: 90));
    });

    test('sem data_registo cai no created_at', () {
      final media = EncomendasRepository.tempoMedioParagemAberta(
        [aberta(createdAt: DateTime(2026, 8, 6, 11, 30))],
        agora: agora,
      );

      expect(media, const Duration(minutes: 30));
    });

    test('incidências sem início nenhum são ignoradas, não contam como zero', () {
      // Contá-las como zero puxava a média para baixo e fazia a fábrica
      // parecer melhor do que está.
      final media = EncomendasRepository.tempoMedioParagemAberta(
        [aberta(inicio: DateTime(2026, 8, 6, 10, 0)), aberta()],
        agora: agora,
      );

      expect(media, const Duration(minutes: 120));
    });

    test('só com incidências sem início devolve null', () {
      expect(
        EncomendasRepository.tempoMedioParagemAberta([aberta()], agora: agora),
        isNull,
      );
    });

    test('a manutenção concluída não pára o contador', () {
      // Entre o fim da manutenção e o line clearance a linha continua parada.
      final media = EncomendasRepository.tempoMedioParagemAberta(
        [
          aberta(
            inicio: DateTime(2026, 8, 6, 10, 0),
            fimManutencao: DateTime(2026, 8, 6, 10, 30),
          ),
        ],
        agora: agora,
      );

      expect(media, const Duration(minutes: 120));
    });

    test('um início no futuro não gera média negativa', () {
      // Relógio do terminal adiantado em relação ao servidor.
      final media = EncomendasRepository.tempoMedioParagemAberta(
        [aberta(inicio: DateTime(2026, 8, 6, 13, 0))],
        agora: agora,
      );

      expect(media, Duration.zero);
    });
  });
}
