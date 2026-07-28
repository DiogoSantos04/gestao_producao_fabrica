import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/cliente_model.dart';
import 'package:gestao_producao_fabrica/models/pedido_model.dart';

void main() {
  group('ClienteModel.fromJson — campos nulos', () {
    test('só com id: os textos ficam nulos e o nome vazio', () {
      final c = ClienteModel.fromJson({'id': 1});

      expect(c.id, 1);
      expect(c.nomeCliente, '');
      expect(c.contacto, isNull);
      expect(c.email, isNull);
      expect(c.nif, isNull);
      expect(c.pessoaContacto, isNull);
      expect(c.morada, isNull);
      expect(c.utilizadorId, isNull);
    });

    test('ativo é falso por omissão — nulo nunca dá acesso ao portal', () {
      expect(ClienteModel.fromJson({'id': 1}).ativo, isFalse);
      expect(ClienteModel.fromJson({'id': 1, 'ativo': null}).ativo, isFalse);
      expect(ClienteModel.fromJson({'id': 1, 'ativo': false}).ativo, isFalse);
      expect(ClienteModel.fromJson({'id': 1, 'ativo': true}).ativo, isTrue);
    });

    test('nome_cliente nulo dá string vazia, não rebenta', () {
      expect(ClienteModel.fromJson({'id': 1, 'nome_cliente': null}).nomeCliente, '');
    });

    test('id aceita o double que o PostgREST pode devolver em web', () {
      expect(ClienteModel.fromJson({'id': 3.0}).id, 3);
    });
  });

  group('ClienteModel.fromJson — junções', () {
    test('sem junções as listas ficam vazias', () {
      final c = ClienteModel.fromJson({'id': 1});

      expect(c.encomendas, isEmpty);
      expect(c.pedidos, isEmpty);
      expect(c.totalEncomendas, 0);
      expect(c.temEncomendas, isFalse);
    });

    test('junções nulas são tratadas como listas vazias', () {
      final c = ClienteModel.fromJson({
        'id': 1,
        'encomendas': null,
        'pedidos_encomenda': null,
      });

      expect(c.encomendas, isEmpty);
      expect(c.pedidos, isEmpty);
    });

    test('encomendas e pedidos são convertidos nos respetivos modelos', () {
      final c = ClienteModel.fromJson({
        'id': 1,
        'encomendas': [
          {'id': 10, 'codigo_rastreio': 'ABC'},
          {'id': 11},
        ],
        'pedidos_encomenda': [
          {'id': 20, 'estado': 'Aprovado'},
        ],
      });

      expect(c.totalEncomendas, 2);
      expect(c.temEncomendas, isTrue);
      expect(c.encomendas.first.codigoRastreio, 'ABC');
      expect(c.pedidos.single.estado, EstadoPedido.aprovado);
    });

    test('elementos não-mapa nas junções são descartados', () {
      final c = ClienteModel.fromJson({
        'id': 1,
        'encomendas': [
          {'id': 10},
          'lixo',
          42,
        ],
      });

      expect(c.totalEncomendas, 1);
    });
  });

  group('ClienteModel.contactoFormatado', () {
    test('contacto nulo ou vazio', () {
      expect(ClienteModel.fromJson({'id': 1}).contactoFormatado, 'Sem contacto');
      expect(
        ClienteModel.fromJson({'id': 1, 'contacto': ''}).contactoFormatado,
        'Sem contacto',
      );
    });

    test('contacto só com letras não deixa dígitos nenhuns', () {
      expect(
        ClienteModel.fromJson({'id': 1, 'contacto': 'sem número'}).contactoFormatado,
        'Sem contacto',
      );
    });

    test('nove dígitos em grupos de três', () {
      expect(
        ClienteModel.fromJson({'id': 1, 'contacto': '912345678'}).contactoFormatado,
        '912 345 678',
      );
    });

    test('indicativo internacional é preservado', () {
      expect(
        ClienteModel.fromJson({'id': 1, 'contacto': '+351912345678'}).contactoFormatado,
        '+351 912 345 678',
      );
    });

    test('separadores já existentes são normalizados', () {
      expect(
        ClienteModel.fromJson({'id': 1, 'contacto': '912-345-678'}).contactoFormatado,
        '912 345 678',
      );
    });
  });

  group('ClienteModel.formatarTelefone', () {
    test('agrupa a cada 3 dígitos', () {
      expect(ClienteModel.formatarTelefone('1'), '1');
      expect(ClienteModel.formatarTelefone('123'), '123');
      expect(ClienteModel.formatarTelefone('1234'), '123 4');
      expect(ClienteModel.formatarTelefone('123456789'), '123 456 789');
      expect(ClienteModel.formatarTelefone('1234567890'), '123 456 789 0');
    });

    test('o + só conta na primeira posição', () {
      expect(ClienteModel.formatarTelefone('+351912'), '+351 912');
      expect(ClienteModel.formatarTelefone('351+912'), '351 912');
    });

    test('string vazia', () {
      expect(ClienteModel.formatarTelefone(''), '');
    });
  });

  group('ClienteModel.corresponde', () {
    final c = ClienteModel.fromJson({
      'id': 1,
      'nome_cliente': 'Fábrica Norte',
      'email': 'geral@norte.pt',
      'contacto': '912345678',
      'nif': '501234567',
      'pessoa_contacto': 'Ana Lima',
      'morada': 'Rua do Porto',
    });

    test('termo vazio corresponde sempre', () {
      expect(c.corresponde(''), isTrue);
    });

    test('procura em todos os campos textuais, sem distinguir maiúsculas', () {
      expect(c.corresponde('norte'), isTrue);
      expect(c.corresponde('GERAL@'), isTrue);
      expect(c.corresponde('9123'), isTrue);
      expect(c.corresponde('5012'), isTrue);
      expect(c.corresponde('ana'), isTrue);
      expect(c.corresponde('porto'), isTrue);
    });

    test('termo ausente não corresponde', () {
      expect(c.corresponde('lisboa'), isFalse);
    });

    test('campos nulos não rebentam a pesquisa', () {
      final vazio = ClienteModel.fromJson({'id': 1});
      expect(vazio.corresponde('seja o que for'), isFalse);
      expect(vazio.corresponde(''), isTrue);
    });
  });

  group('MetricasClientes', () {
    test('por omissão todos os contadores estão a zero', () {
      const m = MetricasClientes();
      expect(m.total, 0);
      expect(m.ativosPortal, 0);
      expect(m.comEncomendas, 0);
      expect(m.totalEncomendas, 0);
    });
  });

  group('FiltroCliente', () {
    test('todos os filtros têm etiqueta não vazia e distinta', () {
      final etiquetas = FiltroCliente.values.map((f) => f.etiqueta).toList();
      expect(etiquetas.every((e) => e.isNotEmpty), isTrue);
      expect(etiquetas.toSet().length, FiltroCliente.values.length);
    });
  });
}
