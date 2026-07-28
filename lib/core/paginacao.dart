/// Uma fatia de resultados vinda do servidor.
///
/// [temMais] é apurado pedindo `tamanho + 1` linhas e descartando a última: evita
/// uma segunda query de `count` só para saber se o botão "Carregar mais" deve
/// aparecer.
class PaginaResultado<T> {
  final List<T> itens;
  final bool temMais;

  const PaginaResultado({required this.itens, required this.temMais});

  /// Constrói a página a partir da resposta com a linha-sentinela ainda incluída.
  factory PaginaResultado.aPartirDeSondagem(List<T> linhas, int tamanho) {
    final bool temMais = linhas.length > tamanho;
    return PaginaResultado(
      itens: temMais ? linhas.sublist(0, tamanho) : linhas,
      temMais: temMais,
    );
  }

  static const PaginaResultado vazia = PaginaResultado(itens: [], temMais: false);
}

/// Número de linhas carregadas de cada vez nas listas paginadas.
///
/// 50 enche mais do que um ecrã em qualquer resolução e mantém o primeiro
/// desenho imediato.
const int tamanhoPaginaPadrao = 50;

/// Intervalo de espera antes de uma pesquisa ir ao servidor.
///
/// Sem isto, cada tecla escrita na caixa de pesquisa dispararia uma query.
const Duration esperaPesquisa = Duration(milliseconds: 300);
