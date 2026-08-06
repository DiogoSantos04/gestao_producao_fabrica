import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/repositories/postos_repository.dart';

void main() {
  PostoResumo posto(int id, String nome, [String estado = EstadoPosto.livre]) =>
      PostoResumo(id: id, nome: nome, estado: estado);

  group('PostosRepository.contarPorEstado', () {
    test('agrupa os postos pelo estado', () {
      final contagem = PostosRepository.contarPorEstado([
        posto(1, 'Corte'),
        posto(2, 'Montagem', EstadoPosto.parado),
        posto(3, 'Pintura', EstadoPosto.emProducao),
        posto(4, 'Secagem'),
      ]);

      expect(contagem, {
        EstadoPosto.livre: 2,
        EstadoPosto.parado: 1,
        EstadoPosto.emProducao: 1,
      });
    });

    test('estados vazios não criam uma categoria em branco', () {
      // Um posto sem estado não é um posto "no estado ''" — seria uma barra
      // sem nome no cartão de disponibilidade.
      final contagem = PostosRepository.contarPorEstado([posto(1, 'Corte', '')]);

      expect(contagem, isEmpty);
    });

    test('sem postos a contagem é vazia, não zero por estado', () {
      expect(PostosRepository.contarPorEstado(const []), isEmpty);
    });
  });

  group('PostosRepository.distribuirOrdens', () {
    final postos = [
      posto(1, 'Corte'),
      posto(2, 'Montagem', EstadoPosto.parado),
      posto(3, 'Pintura', EstadoPosto.emProducao),
    ];

    test('conta as ordens no posto que executa a fase', () {
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: {10: 1, 11: 2, 12: 2},
        fasesAtuais: [10, 11, 12, 11],
      );

      expect(
        {for (final o in ocupacao) o.posto.nome: o.ordens},
        {'Corte': 1, 'Montagem': 3, 'Pintura': 0},
      );
    });

    test('fases distintas do mesmo posto somam na mesma barra', () {
      // É o ponto todo da mudança: "Corte" do produto A e "Corte" do produto B
      // são fases diferentes, mas disputam o mesmo recurso físico.
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: [posto(1, 'Corte')],
        postoPorFase: {10: 1, 20: 1},
        fasesAtuais: [10, 20],
      );

      expect(ocupacao.single.ordens, 2);
    });

    test('postos sem ordens aparecem a zero', () {
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: const {},
        fasesAtuais: const [],
      );

      expect(ocupacao, hasLength(3));
      expect(ocupacao.every((o) => o.ordens == 0), isTrue);
    });

    test('fase sem posto atribuído cai num balde próprio', () {
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: {10: 1},
        fasesAtuais: [10, 99],
      );

      expect(ocupacao.last.posto.id, PostoResumo.idSemPosto);
      expect(ocupacao.last.ordens, 1);
    });

    test('fase que aponta para um posto inexistente também cai no balde', () {
      // Um posto apagado deixa o `posto_trabalho_id` a apontar para o vazio; a
      // ordem existe na mesma e não pode desaparecer do gráfico.
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: {10: 77},
        fasesAtuais: [10],
      );

      expect(ocupacao.last.posto.id, PostoResumo.idSemPosto);
      expect(ocupacao.last.ordens, 1);
    });

    test('sem ordens órfãs o balde não aparece', () {
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: {10: 1},
        fasesAtuais: [10],
      );

      expect(ocupacao, hasLength(3));
      expect(ocupacao.any((o) => o.posto.id == PostoResumo.idSemPosto), isFalse);
    });

    test('a ordem das barras segue a lista de postos', () {
      final ocupacao = PostosRepository.distribuirOrdens(
        postos: postos,
        postoPorFase: const {},
        fasesAtuais: const [],
      );

      expect(ocupacao.map((o) => o.posto.id), [1, 2, 3]);
    });
  });

  group('PostoResumo.parado', () {
    test('só o estado Parado marca o posto como parado', () {
      expect(posto(1, 'A', EstadoPosto.parado).parado, isTrue);
      expect(posto(1, 'A', EstadoPosto.emProducao).parado, isFalse);
      expect(posto(1, 'A', EstadoPosto.livre).parado, isFalse);
    });
  });
}
