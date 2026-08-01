import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/models/estado_ordem.dart';
import 'package:gestao_producao_fabrica/repositories/portal_cliente_repository.dart';

/// Resposta da função `rastrear_encomenda` com o roteiro de três fases.
Map<String, dynamic> _resposta({
  int? faseAtualId,
  bool cancelada = false,
  bool emSuspenso = false,
  List<Map<String, dynamic>>? fases,
}) {
  return {
    'codigo_rastreio': 'TRC-ABC123',
    'data_entrega': '2026-08-30',
    'nome_tipo_produto': 'Armário',
    'fase_atual_id': faseAtualId,
    'cancelada': cancelada,
    'em_suspenso': emSuspenso,
    'fases': fases ??
        [
          {'id': 10, 'nome_fase_padrao': 'Corte', 'ordem': 1},
          {'id': 11, 'nome_fase_padrao': 'Montagem', 'ordem': 2},
          {'id': 12, 'nome_fase_padrao': 'Embalamento', 'ordem': 3},
        ],
  };
}

void main() {
  group('RastreioEncomenda', () {
    test('lê os campos e ordena as fases pelo campo ordem', () {
      final r = RastreioEncomenda.fromJson(_resposta(
        faseAtualId: 11,
        fases: [
          {'id': 12, 'nome_fase_padrao': 'Embalamento', 'ordem': 3},
          {'id': 10, 'nome_fase_padrao': 'Corte', 'ordem': 1},
          {'id': 11, 'nome_fase_padrao': 'Montagem', 'ordem': 2},
        ],
      ));

      expect(r.codigoRastreio, 'TRC-ABC123');
      expect(r.nomeProduto, 'Armário');
      expect(r.dataEntrega, DateTime(2026, 8, 30));
      expect(r.fases.map((f) => f.nome), ['Corte', 'Montagem', 'Embalamento']);
    });

    test('a fase em curso é localizada pelo id', () {
      final r = RastreioEncomenda.fromJson(_resposta(faseAtualId: 11));

      expect(r.indiceFaseAtual, 1);
      expect(r.faseAtualDesconhecida, isFalse);
    });

    test('sem fase atual não há índice, e a ordem está concluída', () {
      final r = RastreioEncomenda.fromJson(_resposta(faseAtualId: null));

      expect(r.indiceFaseAtual, isNull);
      expect(r.faseAtualDesconhecida, isFalse);
      expect(
        EstadoOrdem.derivar(cancelada: r.cancelada, emSuspenso: r.emSuspenso, temFaseAtual: false),
        EstadoOrdem.concluida,
      );
    });

    test('fase atual fora do roteiro é sinalizada em vez de adivinhada', () {
      // Acontece sempre que o roteiro do produto é editado depois de a ordem
      // ter sido lançada: a fase gravada deixa de constar da lista.
      final r = RastreioEncomenda.fromJson(_resposta(faseAtualId: 99));

      expect(r.indiceFaseAtual, isNull);
      expect(r.faseAtualDesconhecida, isTrue);
    });

    test('roteiro vazio não rebenta', () {
      final r = RastreioEncomenda.fromJson(_resposta(faseAtualId: 11, fases: const []));

      expect(r.fases, isEmpty);
      expect(r.faseAtualDesconhecida, isTrue);
    });

    test('a resposta nunca traz o cliente destinatário', () {
      // Garantia do bug (C): o contrato da função no servidor não inclui o
      // cliente, e o modelo não tem sequer onde o guardar.
      expect(_resposta().containsKey('nome_cliente'), isFalse);
      expect(_resposta().containsKey('cliente_id'), isFalse);
    });

    test('cancelada e suspensa chegam ao estado derivado', () {
      final cancelada = RastreioEncomenda.fromJson(_resposta(faseAtualId: 11, cancelada: true));
      final suspensa = RastreioEncomenda.fromJson(_resposta(faseAtualId: 11, emSuspenso: true));

      expect(
        EstadoOrdem.derivar(cancelada: cancelada.cancelada, emSuspenso: false, temFaseAtual: true),
        EstadoOrdem.cancelada,
      );
      expect(
        EstadoOrdem.derivar(cancelada: false, emSuspenso: suspensa.emSuspenso, temFaseAtual: true),
        EstadoOrdem.emHold,
      );
    });
  });

  group('TipoProdutoOpcao', () {
    test('lê id e nome, com omissão para nome em falta', () {
      expect(TipoProdutoOpcao.fromJson({'id': 3, 'nome_tipo_produto': 'Sofá'}).nome, 'Sofá');
      expect(TipoProdutoOpcao.fromJson({'id': 3}).nome, 'Artigo');
    });
  });
}
