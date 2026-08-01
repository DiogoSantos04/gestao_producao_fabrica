import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/repositories/base_repository.dart';

/// Repositório mínimo para exercitar [BaseRepository.guarda] sem tocar na rede.
class _RepositorioDeTeste extends BaseRepository {
  Future<T> correr<T>(Future<T> Function() operacao) => guarda('fazer a operação', operacao);
}

void main() {
  final repo = _RepositorioDeTeste();

  group('BaseRepository.guarda', () {
    test('devolve o valor quando a operação corre bem', () async {
      expect(await repo.correr(() async => 42), 42);
    });

    test('preserva a mensagem de negócio de uma RepositoryException', () async {
      // Uma operação que reconhece o código de uma restrição (por exemplo, a
      // avaliação duplicada) traduz o erro ela própria. Reembrulhá-lo aqui
      // trocaria essa mensagem pelo texto genérico do `catch` final.
      await expectLater(
        repo.correr(() async => throw const RepositoryException('Esta encomenda já foi avaliada.')),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.mensagem,
            'mensagem',
            'Esta encomenda já foi avaliada.',
          ),
        ),
      );
    });

    test('um erro desconhecido vira mensagem genérica com o contexto', () async {
      await expectLater(
        repo.correr(() async => throw StateError('boom')),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.mensagem,
            'mensagem',
            'Falha ao fazer a operação.',
          ),
        ),
      );
    });
  });
}
