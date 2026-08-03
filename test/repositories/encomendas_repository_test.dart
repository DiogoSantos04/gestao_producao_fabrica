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
}
