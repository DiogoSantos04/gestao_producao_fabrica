import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';

/// Cartão branco com título, subtítulo opcional e conteúdo.
///
/// Os painéis do ecrã de planeamento repetiam a mesma `Card` com a mesma borda,
/// o mesmo raio e o mesmo cabeçalho três vezes.
class CartaoPainel extends StatelessWidget {
  const CartaoPainel({
    super.key,
    required this.titulo,
    required this.conteudo,
    this.subtitulo,
    this.expandirConteudo = true,
    this.alturaConteudo,
    this.padding = const EdgeInsets.all(24),
  });

  final String titulo;
  final String? subtitulo;
  final Widget conteudo;

  /// Em desktop o conteúdo ocupa o espaço disponível; em ecrãs estreitos fica
  /// com altura fixa dentro de uma coluna que faz scroll.
  final bool expandirConteudo;
  final double? alturaConteudo;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: TemasCores.superficie,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: TemasCores.borda),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            ),
            if (subtitulo != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitulo!,
                style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciario),
              ),
            ],
            const SizedBox(height: 16),
            expandirConteudo
                ? Expanded(child: conteudo)
                : SizedBox(height: alturaConteudo, child: conteudo),
          ],
        ),
      ),
    );
  }
}
