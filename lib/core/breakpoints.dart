import 'package:flutter/material.dart';

/// Breakpoints partilhados por toda a app.
///
/// Antes desta constante, cada ecrã inventava o seu próprio corte (950, 900,
/// 850, 760, 650, 600, 560...), sem relação entre si. `medio` mantém-se em
/// 950 de propósito: é o valor já usado pelos quatro shells de navegação
/// (drawer vs sidebar fixa) e mudá-lo alteraria um corte que já funciona.
abstract class Breakpoints {
  static const double compacto = 600;
  static const double medio = 950;
}

/// Leituras de tamanho de ecrã e valores adaptativos derivados dele.
extension ContextoResponsivo on BuildContext {
  double get larguraEcra => MediaQuery.sizeOf(this).width;

  /// Telemóvel: menos espaço do que qualquer diálogo ou tabela de desktop
  /// consegue assumir sem se adaptar.
  bool get ehCompacto => larguraEcra < Breakpoints.compacto;

  /// Acima disto é o corte que os shells já usam para a sidebar fixa.
  bool get ehAmplo => larguraEcra > Breakpoints.medio;
}

/// Largura de diálogo que cabe no ecrã.
///
/// Diálogos com `SizedBox(width: N)` fixo estouravam em qualquer telemóvel
/// com menos de N pixels úteis — o diálogo abria mais largo do que o ecrã.
double larguraDialogo(BuildContext context, double preferida) {
  return preferida < context.larguraEcra - 32 ? preferida : context.larguraEcra - 32;
}

/// Padding horizontal/vertical adaptativo para o corpo dos ecrãs.
///
/// Substitui os `EdgeInsets.all(24)`/`EdgeInsets.all(40)` fixos que comiam
/// espaço útil a mais em telemóvel.
EdgeInsets paddingEcra(BuildContext context) {
  if (context.ehCompacto) return const EdgeInsets.all(16);
  if (context.ehAmplo) return const EdgeInsets.all(40);
  return const EdgeInsets.all(24);
}
