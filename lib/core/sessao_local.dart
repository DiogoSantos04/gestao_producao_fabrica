/// Marca os términos de sessão pedidos pela própria aplicação.
///
/// O `VigilanteSessao` escuta `onAuthStateChange` para apanhar sessões perdidas
/// de forma involuntária (token expirado, credencial revogada) e encaminhar para
/// o login. Mas um logout carregado no botão — ou o `signOut` que fecha a sessão
/// aberta automaticamente por um `signUp` — gera exatamente o mesmo evento. Sem
/// esta marca, cada um deles dava uma navegação a mais e uma mensagem de erro
/// que não corresponde a nada.
///
/// É uma marca temporal, e não um booleano, para não ficar presa: se o `signOut`
/// falhar a meio, expira sozinha em vez de mascarar a perda de sessão seguinte.
class SessaoLocal {
  SessaoLocal._();

  static const Duration _janela = Duration(seconds: 5);

  static DateTime? _marca;

  /// A chamar imediatamente antes de qualquer `signOut` feito pela aplicação.
  static void marcarTerminoIntencional() => _marca = DateTime.now();

  /// Consome a marca. Devolve `true` se o término foi pedido pela aplicação.
  static bool consumirTerminoIntencional() {
    final marca = _marca;
    if (marca == null) return false;
    _marca = null;
    return DateTime.now().difference(marca) < _janela;
  }
}
