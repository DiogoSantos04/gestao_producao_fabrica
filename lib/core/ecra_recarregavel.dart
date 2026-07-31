/// Ecrã que sabe voltar a ler os seus dados a pedido de quem o contém.
///
/// O terminal do operador mantém os separadores vivos num `IndexedStack` — sair
/// e voltar não os reconstrói, o que preserva o scroll e os filtros mas também
/// preserva os dados. Sem uma forma de pedir o recarregamento, um separador
/// podia ficar a mostrar o estado de há horas.
///
/// Implementado pela `State` do ecrã e chamado através de uma `GlobalKey`.
abstract class EcraRecarregavel {
  Future<void> recarregar();
}
