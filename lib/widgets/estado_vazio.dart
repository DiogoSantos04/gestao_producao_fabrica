import 'package:flutter/material.dart';

import '../core/temas_cores.dart';

/// Estado "não há nada para mostrar", apresentado como cartão.
///
/// Distinto de [EstadoErro]: aqui o carregamento correu bem e o resultado é
/// mesmo vazio. Antes cada ecrã resolvia isto com um ícone solto e uma linha de
/// texto centrada no meio do fundo, sem contorno — que se lia como um ecrã por
/// acabar em vez de uma resposta.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    this.descricao,
    this.corIcone = TemasCores.textoTerciarioFrio,
    this.corFundoIcone = TemasCores.superficieSuave,
    this.acao,
  });

  final IconData icone;
  final String titulo;
  final String? descricao;
  final Color corIcone;
  final Color corFundoIcone;

  /// Botão opcional (atualizar, criar o primeiro registo, limpar filtros).
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: corFundoIcone,
              shape: BoxShape.circle,
            ),
            child: Icon(icone, size: 32, color: corIcone),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: TemasCores.textoPrimarioFrio,
            ),
          ),
          if (descricao != null) ...[
            const SizedBox(height: 6),
            Text(
              descricao!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: TemasCores.textoSecundarioFrio,
              ),
            ),
          ],
          if (acao != null) ...[
            const SizedBox(height: 20),
            acao!,
          ],
        ],
      ),
    );
  }
}
