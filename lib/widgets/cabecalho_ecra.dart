import 'package:flutter/material.dart';

import '../core/temas_cores.dart';

/// Cabeçalho de um ecrã de conteúdo: ícone de marca, título, linha de contexto
/// e, se fizer sentido, um botão de atualizar.
///
/// Existe porque vários ecrãs abriam diretamente na lista, sem nada que dissesse
/// o que ali estava nem quantos itens eram — o único título era o da AppBar, que
/// desaparece assim que o ecrã ganha uma barra lateral fixa.
class CabecalhoEcra extends StatelessWidget {
  const CabecalhoEcra({
    super.key,
    required this.icone,
    required this.titulo,
    required this.acento,
    this.subtitulo,
    this.aoAtualizar,
    this.acaoExtra,
  });

  final IconData icone;
  final String titulo;

  /// Linha de contexto por baixo do título (contagens, estado, explicação).
  final String? subtitulo;

  /// Cor de marca do perfil (operador, técnico, cliente, admin).
  final Color acento;

  /// Botão de atualizar. Omitido quando o ecrã não recarrega à mão.
  final Future<void> Function()? aoAtualizar;

  /// Ação própria do ecrã, colocada à direita do botão de atualizar.
  final Widget? acaoExtra;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: acento.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icone, color: acento, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: TemasCores.textoPrimarioFrio,
                ),
              ),
              if (subtitulo != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitulo!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: TemasCores.textoSecundarioFrio,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (aoAtualizar != null)
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => aoAtualizar!(),
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: TemasCores.textoSecundarioFrio,
          ),
        if (acaoExtra != null) ...[
          const SizedBox(width: 4),
          acaoExtra!,
        ],
      ],
    );
  }
}
