import 'package:flutter/material.dart';

import 'estado_erro.dart';

/// Rodapé de uma lista paginada.
///
/// O scroll já dispara o carregamento sozinho ao aproximar-se do fim; o botão
/// existe como saída manual para o caso de a janela ser alta o suficiente para
/// a página caber sem haver scroll nenhum.
class RodapePaginacao extends StatelessWidget {
  const RodapePaginacao({
    super.key,
    required this.aCarregar,
    required this.erro,
    required this.aoCarregarMais,
    this.tituloErro = 'Não foi possível carregar mais resultados.',
  });

  final bool aCarregar;

  /// Motivo da falha da última página, ou `null` se correu bem.
  final String? erro;

  final VoidCallback aoCarregarMais;
  final String tituloErro;

  @override
  Widget build(BuildContext context) {
    // Se a página seguinte falhou, o rodapé deixa de convidar ao scroll infinito
    // (que voltaria a falhar em silêncio) e passa a dizer o que aconteceu.
    if (erro != null && !aCarregar) {
      return EstadoErro.compacto(
        titulo: tituloErro,
        detalhe: erro,
        aoRepetir: aoCarregarMais,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: aCarregar
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: aoCarregarMais,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('Carregar mais', style: TextStyle(fontSize: 13)),
              ),
      ),
    );
  }
}
