import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_producao_fabrica/screens/dashboard_admin/dashboard_principal_screen.dart';

void main() {
  group('descreverVariacaoDiaria', () {
    test('subida mostra o sinal e o valor de ontem', () {
      expect(descreverVariacaoDiaria(5, 3), '+2 vs ontem (3)');
    });

    test('descida usa o sinal de menos tipográfico', () {
      // O hífen normal alinha mal ao lado dos dígitos no subtítulo.
      expect(descreverVariacaoDiaria(1, 4), '−3 vs ontem (4)');
    });

    test('empate diz que está igual', () {
      expect(descreverVariacaoDiaria(4, 4), 'Igual a ontem (4)');
    });

    test('zero e zero não é "igual a ontem"', () {
      // Dois dias sem produzir nada não é estabilidade; dizer "igual a ontem"
      // mascarava uma linha parada.
      expect(descreverVariacaoDiaria(0, 0), 'Nada concluído ontem nem hoje');
    });

    test('primeiro dia com produção parte de zero', () {
      expect(descreverVariacaoDiaria(3, 0), '+3 vs ontem (0)');
    });

    test('cair para zero é reportado', () {
      expect(descreverVariacaoDiaria(0, 2), '−2 vs ontem (2)');
    });
  });
}
