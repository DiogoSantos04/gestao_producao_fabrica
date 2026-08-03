import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/core/realtime.dart';

const _janela = Duration(milliseconds: 300);
const _teto = Duration(milliseconds: 1500);

/// Contador de recarregamentos que terminam de imediato.
class _Contador {
  int chamadas = 0;
  Future<void> call() async => chamadas++;
}

/// Recarregamento que só termina quando o teste mandar, para exercitar o caso
/// de um pedido estar no ar quando chega novo evento.
class _Controlado {
  int chamadas = 0;
  final List<Completer<void>> pedidos = [];

  Future<void> call() {
    chamadas++;
    final c = Completer<void>();
    pedidos.add(c);
    return c.future;
  }

  void terminarUltimo() => pedidos.last.complete();
}

RecarregadorDebounced _criar(Future<void> Function() aoRecarregar) {
  return RecarregadorDebounced(
    aoRecarregar: aoRecarregar,
    janela: _janela,
    tetoEspera: _teto,
  );
}

void main() {
  group('RecarregadorDebounced — aresta inicial', () {
    test('o primeiro pedido corre já, sem esperar pela janela', () {
      fakeAsync((async) {
        final c = _Contador();
        _criar(c.call).pedir();

        async.flushMicrotasks();
        expect(c.chamadas, 1);
      });
    });

    test('dois pedidos separados por mais do que a janela são dois recarregamentos', () {
      fakeAsync((async) {
        final c = _Contador();
        final r = _criar(c.call);

        r.pedir();
        async.elapse(_janela * 2);
        r.pedir();
        async.flushMicrotasks();

        expect(c.chamadas, 2);
      });
    });
  });

  group('RecarregadorDebounced — coalescência', () {
    test('uma rajada dentro da janela dá um recarregamento imediato e um só no fim', () {
      fakeAsync((async) {
        final c = _Contador();
        final r = _criar(c.call);

        // Avançar uma fase gera dois ou três eventos em dezenas de ms.
        r.pedir();
        async.elapse(const Duration(milliseconds: 20));
        r.pedir();
        async.elapse(const Duration(milliseconds: 20));
        r.pedir();
        async.flushMicrotasks();

        expect(c.chamadas, 1, reason: 'ainda só correu a aresta inicial');

        async.elapse(_janela);
        expect(c.chamadas, 2, reason: 'os dois eventos seguintes fundiram-se num só');
      });
    });

    test('janela sem eventos novos fecha sem recarregar outra vez', () {
      fakeAsync((async) {
        final c = _Contador();
        _criar(c.call).pedir();

        async.elapse(_janela * 3);
        expect(c.chamadas, 1);
      });
    });
  });

  group('RecarregadorDebounced — teto de rajada', () {
    test('uma rajada contínua não adia o ecrã além do teto', () {
      fakeAsync((async) {
        final c = _Contador();
        final r = _criar(c.call);

        r.pedir();
        // Um evento a cada 100 ms durante 2 s: a janela nunca chegaria a fechar
        // sozinha, por isso é o teto que tem de disparar o recarregamento.
        for (var i = 0; i < 20; i++) {
          async.elapse(const Duration(milliseconds: 100));
          r.pedir();
        }
        async.flushMicrotasks();

        expect(c.chamadas, greaterThan(1));
        expect(
          c.chamadas,
          lessThan(20),
          reason: 'sem coalescência seriam 21 recarregamentos',
        );
      });
    });
  });

  group('RecarregadorDebounced — pedidos sobrepostos', () {
    test('um evento durante um pedido no ar não lança um segundo em paralelo', () {
      fakeAsync((async) {
        final c = _Controlado();
        final r = _criar(c.call);

        r.pedir();
        async.flushMicrotasks();
        expect(c.chamadas, 1);

        // Chega novo evento com o primeiro pedido ainda por responder.
        r.pedir();
        async.elapse(_janela);
        expect(c.chamadas, 1, reason: 'o primeiro ainda está no ar');

        c.terminarUltimo();
        async.elapse(_janela);
        expect(c.chamadas, 2, reason: 'corre depois de o anterior ter terminado');
      });
    });

    test('vários eventos durante o mesmo pedido dão um único recarregamento a seguir', () {
      fakeAsync((async) {
        final c = _Controlado();
        final r = _criar(c.call);

        r.pedir();
        async.flushMicrotasks();

        r.pedir();
        r.pedir();
        r.pedir();
        async.elapse(_janela);

        c.terminarUltimo();
        async.elapse(_janela);
        expect(c.chamadas, 2);
      });
    });
  });

  group('RecarregadorDebounced — falhas', () {
    test('um recarregamento que rebenta não deixa o recarregador preso', () {
      fakeAsync((async) {
        var chamadas = 0;
        final r = _criar(() async {
          chamadas++;
          throw StateError('rede em baixo');
        });

        r.pedir();
        async.flushMicrotasks();
        expect(chamadas, 1);

        r.pedir();
        async.elapse(_janela);
        async.flushMicrotasks();
        expect(chamadas, 2, reason: '_aCorrer foi reposto no finally');
      });
    });
  });

  group('RecarregadorDebounced — descartar', () {
    test('descartar cancela o recarregamento agendado', () {
      fakeAsync((async) {
        final c = _Contador();
        final r = _criar(c.call);

        r.pedir();
        async.flushMicrotasks();
        r.pedir();
        r.descartar();

        async.elapse(_janela * 5);
        expect(c.chamadas, 1, reason: 'o pendente foi descartado com o ecrã');
      });
    });

    test('pedir depois de descartar não faz nada', () {
      fakeAsync((async) {
        final c = _Contador();
        final r = _criar(c.call);

        r.descartar();
        r.pedir();

        async.elapse(_janela * 5);
        expect(c.chamadas, 0);
      });
    });

    test('descartar duas vezes é seguro', () {
      final r = _criar(_Contador().call);
      r.descartar();
      expect(r.descartar, returnsNormally);
    });
  });

  group('Constantes de temporização', () {
    test('o teto é sempre maior do que a janela que fecha', () {
      // Um teto menor do que a janela anularia a coalescência: cada evento
      // dispararia logo o recarregamento.
      expect(tetoRealtimeLista, greaterThan(janelaRealtimeLista));
      expect(tetoRealtimeAgregado, greaterThan(janelaRealtimeAgregado));
      expect(tetoRealtimeCarteira, greaterThan(janelaRealtimeCarteira));
    });

    test('as listas reagem mais depressa do que os ecrãs agregados', () {
      expect(janelaRealtimeLista, lessThan(janelaRealtimeCarteira));
      expect(janelaRealtimeCarteira, lessThan(janelaRealtimeAgregado));
    });
  });
}
