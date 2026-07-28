import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/widgets/estado_erro.dart';

/// Substitui o `widget_test.dart` gerado pelo Flutter, que testava um contador
/// que nunca existiu nesta aplicação.
///
/// O `EstadoErro` é o único widget da app sem dependências de rede ou de estado
/// de ecrã, e o que carrega a regra mais importante: uma falha tem de ser
/// visível e tem de ter saída. É por isso o que faz sentido testar aqui.
void main() {
  Future<void> montar(WidgetTester tester, Widget filho) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: filho)));
  }

  group('EstadoErro — forma completa', () {
    testWidgets('mostra o título por omissão e o botão de repetir', (tester) async {
      await montar(tester, EstadoErro(aoRepetir: () {}));

      expect(find.text('Não foi possível carregar os dados'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
    });

    testWidgets('o botão chama aoRepetir', (tester) async {
      var vezes = 0;
      await montar(tester, EstadoErro(aoRepetir: () => vezes++));

      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();

      expect(vezes, 1);
    });

    testWidgets('título próprio substitui o por omissão', (tester) async {
      await montar(
        tester,
        EstadoErro(aoRepetir: () {}, titulo: 'Falhou a carteira de clientes'),
      );

      expect(find.text('Falhou a carteira de clientes'), findsOneWidget);
      expect(find.text('Não foi possível carregar os dados'), findsNothing);
    });

    testWidgets('o detalhe técnico aparece quando existe', (tester) async {
      await montar(
        tester,
        EstadoErro(aoRepetir: () {}, detalhe: 'Ligação recusada pelo servidor'),
      );

      expect(find.text('Ligação recusada pelo servidor'), findsOneWidget);
    });

    testWidgets('detalhe nulo ou vazio não ocupa espaço', (tester) async {
      await montar(tester, EstadoErro(aoRepetir: () {}, detalhe: ''));

      // Só o título e a etiqueta do botão.
      expect(find.byType(Text), findsNWidgets(2));
    });
  });

  group('EstadoErro.compacto', () {
    testWidgets('usa a etiqueta curta do botão', (tester) async {
      await montar(tester, EstadoErro.compacto(aoRepetir: () {}));

      expect(find.text('Repetir'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);
    });

    testWidgets('o botão chama aoRepetir', (tester) async {
      var vezes = 0;
      await montar(tester, EstadoErro.compacto(aoRepetir: () => vezes++));

      await tester.tap(find.text('Repetir'));
      await tester.pump();

      expect(vezes, 1);
    });

    testWidgets('mostra o título, mas nunca o detalhe técnico', (tester) async {
      await montar(
        tester,
        EstadoErro.compacto(
          aoRepetir: () {},
          titulo: 'Atualização falhada',
          detalhe: 'Ligação recusada pelo servidor',
        ),
      );

      expect(find.text('Atualização falhada'), findsOneWidget);
      expect(find.text('Ligação recusada pelo servidor'), findsNothing);
    });
  });

  group('descreverErro', () {
    test('tira o prefixo Exception:', () {
      expect(descreverErro(Exception('falhou a ligação')), 'falhou a ligação');
    });

    test('tira também os prefixos com nome próprio', () {
      expect(descreverErro(const FormatException('data inválida')),
          contains('data inválida'));
      expect(descreverErro('PostgrestException: coluna inexistente'),
          'coluna inexistente');
    });

    test('texto sem prefixo passa intacto', () {
      expect(descreverErro('sem rede'), 'sem rede');
    });

    test('corta aos 160 caracteres e sinaliza com reticências', () {
      final resultado = descreverErro('x' * 300);

      expect(resultado.length, 161);
      expect(resultado.endsWith('…'), isTrue);
    });

    test('160 caracteres exatos não são cortados', () {
      final resultado = descreverErro('x' * 160);

      expect(resultado.length, 160);
      expect(resultado.endsWith('…'), isFalse);
    });

    test('espaços à volta são removidos', () {
      expect(descreverErro('   sem rede   '), 'sem rede');
    });
  });
}
