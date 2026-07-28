import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/pedido_model.dart';

void main() {
  group('EstadoPedido.desdeTexto', () {
    test('nulo e vazio caem em pendente', () {
      expect(EstadoPedido.desdeTexto(null), EstadoPedido.pendente);
      expect(EstadoPedido.desdeTexto(''), EstadoPedido.pendente);
      expect(EstadoPedido.desdeTexto('   '), EstadoPedido.pendente);
    });

    test('valor desconhecido cai em pendente, nunca em aprovado', () {
      expect(EstadoPedido.desdeTexto('qualquer coisa'), EstadoPedido.pendente);
    });

    test('não distingue maiúsculas nem espaços à volta', () {
      expect(EstadoPedido.desdeTexto('  APROVADO '), EstadoPedido.aprovado);
      expect(EstadoPedido.desdeTexto('rejeitado'), EstadoPedido.rejeitado);
    });

    test('tolera sufixos — era o que o .ilike("Aprovado%") fazia na query', () {
      expect(EstadoPedido.desdeTexto('Aprovado em 12/03'), EstadoPedido.aprovado);
      expect(EstadoPedido.desdeTexto('Rejeitado pelo admin'), EstadoPedido.rejeitado);
    });

    test('"Em Produção" com e sem acento', () {
      expect(EstadoPedido.desdeTexto('Em Produção'), EstadoPedido.emProducao);
      expect(EstadoPedido.desdeTexto('Em Producao'), EstadoPedido.emProducao);
    });

    test('valorBd volta a dar o mesmo estado — ida e volta estável', () {
      for (final e in EstadoPedido.values) {
        expect(EstadoPedido.desdeTexto(e.valorBd), e);
      }
    });

    test('a etiqueta apresentada é o próprio valor gravado na BD', () {
      for (final e in EstadoPedido.values) {
        expect(e.etiqueta, e.valorBd);
      }
    });

    test('só o pendente aguarda decisão', () {
      expect(EstadoPedido.pendente.aguardaDecisao, isTrue);
      expect(EstadoPedido.aprovado.aguardaDecisao, isFalse);
      expect(EstadoPedido.emProducao.aguardaDecisao, isFalse);
      expect(EstadoPedido.rejeitado.aguardaDecisao, isFalse);
    });
  });

  group('PedidoModel.fromJson — campos nulos', () {
    test('só com id', () {
      final p = PedidoModel.fromJson({'id': 1});

      expect(p.id, 1);
      expect(p.createdAt, isNull);
      expect(p.clienteId, isNull);
      expect(p.tipoProdutoId, isNull);
      expect(p.quantidade, 1);
      expect(p.observacoes, isNull);
      expect(p.estado, EstadoPedido.pendente);
      expect(p.nomeCliente, isNull);
      expect(p.emailCliente, isNull);
      expect(p.nomeProduto, isNull);
    });

    test('quantidade nula cai em 1', () {
      expect(PedidoModel.fromJson({'id': 1, 'quantidade': null}).quantidade, 1);
      expect(PedidoModel.fromJson({'id': 1, 'quantidade': 50}).quantidade, 50);
    });

    test('created_at inválido fica nulo em vez de rebentar', () {
      expect(PedidoModel.fromJson({'id': 1, 'created_at': 'xpto'}).createdAt, isNull);
      expect(
        PedidoModel.fromJson({'id': 1, 'created_at': '2026-04-01T10:30:00'}).createdAt,
        DateTime(2026, 4, 1, 10, 30),
      );
    });
  });

  group('PedidoModel.fromJson — junções', () {
    test('cliente e produto como objeto', () {
      final p = PedidoModel.fromJson({
        'id': 1,
        'clientes': {'nome_cliente': 'Fábrica Sul', 'email': 'sul@fab.pt'},
        'tipos_produto': {'nome_tipo_produto': 'Mesa'},
      });

      expect(p.nomeCliente, 'Fábrica Sul');
      expect(p.emailCliente, 'sul@fab.pt');
      expect(p.nomeProduto, 'Mesa');
    });

    test('cliente como lista de um elemento é desembrulhado', () {
      final p = PedidoModel.fromJson({
        'id': 1,
        'clientes': [
          {'nome_cliente': 'Fábrica Sul'},
        ],
      });

      expect(p.nomeCliente, 'Fábrica Sul');
    });

    test('junção nula ou lista vazia deixa os campos nulos', () {
      final p = PedidoModel.fromJson({'id': 1, 'clientes': null, 'tipos_produto': []});

      expect(p.nomeCliente, isNull);
      expect(p.nomeProduto, isNull);
    });
  });

  group('PedidoModel.temObservacoes', () {
    test('nulo, vazio e só espaços não contam', () {
      expect(PedidoModel.fromJson({'id': 1}).temObservacoes, isFalse);
      expect(PedidoModel.fromJson({'id': 1, 'observacoes': ''}).temObservacoes, isFalse);
      expect(
        PedidoModel.fromJson({'id': 1, 'observacoes': '   '}).temObservacoes,
        isFalse,
      );
    });

    test('texto útil conta', () {
      expect(
        PedidoModel.fromJson({'id': 1, 'observacoes': 'urgente'}).temObservacoes,
        isTrue,
      );
    });
  });
}
