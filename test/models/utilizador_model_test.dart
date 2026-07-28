import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/utilizador_model.dart';

void main() {
  group('PerfilUtilizador.desdeTexto', () {
    test('variantes históricas de administrador', () {
      expect(PerfilUtilizador.desdeTexto('Admin'), PerfilUtilizador.administrador);
      expect(PerfilUtilizador.desdeTexto('administrador'), PerfilUtilizador.administrador);
      expect(PerfilUtilizador.desdeTexto('  ADMIN '), PerfilUtilizador.administrador);
    });

    test('variantes históricas de operador, com e sem acento', () {
      expect(PerfilUtilizador.desdeTexto('Operador'), PerfilUtilizador.operador);
      expect(PerfilUtilizador.desdeTexto('Funcionario'), PerfilUtilizador.operador);
      expect(PerfilUtilizador.desdeTexto('Funcionário'), PerfilUtilizador.operador);
    });

    test('cliente', () {
      expect(PerfilUtilizador.desdeTexto('Cliente'), PerfilUtilizador.cliente);
    });

    test('nulo e desconhecido não dão administrador', () {
      expect(PerfilUtilizador.desdeTexto(null), PerfilUtilizador.desconhecido);
      expect(PerfilUtilizador.desdeTexto(''), PerfilUtilizador.desconhecido);
      expect(PerfilUtilizador.desdeTexto('chefe'), PerfilUtilizador.desconhecido);
    });

    test('o perfil desconhecido comporta-se como operador na UI e na BD', () {
      expect(
        PerfilUtilizador.desconhecido.etiqueta,
        PerfilUtilizador.operador.etiqueta,
      );
      expect(PerfilUtilizador.desconhecido.valorBd, PerfilUtilizador.operador.valorBd);
    });

    test('valorBd dos perfis reais volta a dar o mesmo perfil', () {
      for (final p in [
        PerfilUtilizador.administrador,
        PerfilUtilizador.operador,
        PerfilUtilizador.cliente,
      ]) {
        expect(PerfilUtilizador.desdeTexto(p.valorBd), p);
      }
    });
  });

  group('EstadoConta.desdeTexto', () {
    test('ativo e inativo', () {
      expect(EstadoConta.desdeTexto('Ativo'), EstadoConta.ativo);
      expect(EstadoConta.desdeTexto('  ativo '), EstadoConta.ativo);
      expect(EstadoConta.desdeTexto('Inativo'), EstadoConta.inativo);
    });

    test('falha fechado: nulo, vazio e desconhecido dão pendente', () {
      // É o travão de acesso do AuthService — nunca pode cair em ativo.
      expect(EstadoConta.desdeTexto(null), EstadoConta.pendente);
      expect(EstadoConta.desdeTexto(''), EstadoConta.pendente);
      expect(EstadoConta.desdeTexto('bloqueado'), EstadoConta.pendente);
      expect(EstadoConta.desdeTexto('ATIVO_MAS_NAO'), EstadoConta.pendente);
    });

    test('valorBd volta a dar o mesmo estado', () {
      for (final e in EstadoConta.values) {
        expect(EstadoConta.desdeTexto(e.valorBd), e);
      }
    });
  });

  group('UtilizadorModel.fromJson — campos nulos', () {
    test('só com utilizador_id: perfil e estado caem nos valores seguros', () {
      final u = UtilizadorModel.fromJson({'utilizador_id': 'uuid-1'});

      expect(u.utilizadorId, 'uuid-1');
      expect(u.nomeUtilizador, '');
      expect(u.email, isNull);
      expect(u.perfil, PerfilUtilizador.desconhecido);
      expect(u.estadoConta, EstadoConta.pendente);
    });

    test('nome nulo dá string vazia', () {
      final u = UtilizadorModel.fromJson({
        'utilizador_id': 'uuid-1',
        'nome_utilizador': null,
      });
      expect(u.nomeUtilizador, '');
    });

    test('campos completos', () {
      final u = UtilizadorModel.fromJson({
        'utilizador_id': 'uuid-2',
        'nome_utilizador': 'Diogo Santos',
        'email': 'diogo@fab.pt',
        'perfil': 'Admin',
        'estado_conta': 'Ativo',
      });

      expect(u.perfil, PerfilUtilizador.administrador);
      expect(u.estadoConta, EstadoConta.ativo);
      expect(u.email, 'diogo@fab.pt');
    });
  });

  group('UtilizadorModel.iniciais', () {
    String iniciaisDe(String nome) =>
        UtilizadorModel(utilizadorId: 'x', nomeUtilizador: nome).iniciais;

    test('primeiro e último nome', () {
      expect(iniciaisDe('Diogo Santos'), 'DS');
      expect(iniciaisDe('Ana Maria Lima Costa'), 'AC');
    });

    test('nome único dá uma letra', () {
      expect(iniciaisDe('Diogo'), 'D');
    });

    test('espaços a mais não produzem partes vazias', () {
      expect(iniciaisDe('  Diogo   Santos  '), 'DS');
    });

    test('nome vazio dá interrogação em vez de rebentar', () {
      expect(iniciaisDe(''), '?');
      expect(iniciaisDe('   '), '?');
    });

    test('resultado é sempre maiúsculo', () {
      expect(iniciaisDe('diogo santos'), 'DS');
    });
  });

  group('UtilizadorModel.copyWith', () {
    const base = UtilizadorModel(
      utilizadorId: 'uuid-1',
      nomeUtilizador: 'Ana',
      email: 'ana@fab.pt',
      perfil: PerfilUtilizador.operador,
      estadoConta: EstadoConta.pendente,
    );

    test('sem argumentos mantém tudo', () {
      final c = base.copyWith();
      expect(c.utilizadorId, base.utilizadorId);
      expect(c.nomeUtilizador, base.nomeUtilizador);
      expect(c.email, base.email);
      expect(c.perfil, base.perfil);
      expect(c.estadoConta, base.estadoConta);
    });

    test('substitui apenas o que recebe', () {
      final c = base.copyWith(estadoConta: EstadoConta.ativo);
      expect(c.estadoConta, EstadoConta.ativo);
      expect(c.perfil, PerfilUtilizador.operador);
      expect(c.nomeUtilizador, 'Ana');
    });

    test('o id e o email não são alteráveis por copyWith', () {
      final c = base.copyWith(nomeUtilizador: 'Ana Silva');
      expect(c.utilizadorId, 'uuid-1');
      expect(c.email, 'ana@fab.pt');
    });
  });
}
