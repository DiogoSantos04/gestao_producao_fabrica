import 'package:flutter/material.dart';

import '../core/temas_cores.dart';

/// Estado de erro de carregamento, com botão de repetir.
///
/// Existe porque uma falha de rede mostrada apenas num SnackBar desaparece ao
/// fim de 4 segundos e deixa a lista vazia — indistinguível de "não há dados".
/// Quem olha para o ecrã tem de conseguir perceber, a qualquer momento, que o
/// que está a ver é uma falha e não um resultado, e tem de ter forma de tentar
/// outra vez sem sair do ecrã.
///
/// Duas formas:
/// - [EstadoErro] ocupa o espaço onde os dados deviam estar (o corpo do ecrã,
///   um painel, uma coluna);
/// - [EstadoErro.compacto] é uma barra fina, para quando já há dados no ecrã e
///   o que falhou foi um pedido adicional (a página seguinte de uma lista, um
///   painel lateral).
class EstadoErro extends StatelessWidget {
  const EstadoErro({
    super.key,
    required this.aoRepetir,
    this.titulo = 'Não foi possível carregar os dados',
    this.detalhe,
    this.icone = Icons.cloud_off_rounded,
    this.compacto = false,
  });

  /// Barra fina para falhas parciais, com o ecrã já preenchido.
  const EstadoErro.compacto({
    super.key,
    required this.aoRepetir,
    this.titulo = 'Não foi possível carregar os dados',
    this.detalhe,
    this.icone = Icons.cloud_off_rounded,
  }) : compacto = true;

  /// Chamado pelo botão "Tentar novamente". Normalmente é a mesma função de
  /// carregamento que falhou — nada na lógica de carregamento muda por causa
  /// deste widget.
  final VoidCallback aoRepetir;

  /// O que falhou, em linguagem do utilizador.
  final String titulo;

  /// Motivo técnico. Opcional: só ajuda quem está a diagnosticar, pelo que é
  /// apresentado em segundo plano e nunca substitui o [titulo].
  final String? detalhe;

  final IconData icone;

  final bool compacto;

  @override
  Widget build(BuildContext context) {
    return compacto ? _construirCompacto() : _construirCompleto();
  }

  Widget _construirCompleto() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: TemasCores.erroFundo,
                shape: BoxShape.circle,
              ),
              child: Icon(icone, size: 36, color: TemasCores.erroForte),
            ),
            const SizedBox(height: 20),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: TemasCores.textoPrimario,
              ),
            ),
            if (detalhe != null && detalhe!.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  detalhe!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: TemasCores.textoSecundario,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: aoRepetir,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar novamente'),
              style: ElevatedButton.styleFrom(
                backgroundColor: TemasCores.marcaEscura,
                foregroundColor: TemasCores.textoInverso,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirCompacto() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: TemasCores.erroFundo,
        border: Border.all(color: TemasCores.erroBorda),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icone, size: 18, color: TemasCores.erroForte),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: TemasCores.erroTextoForte,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: aoRepetir,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Repetir'),
            style: TextButton.styleFrom(
              foregroundColor: TemasCores.erroTextoForte,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reduz a exceção ao que é legível: o `Exception:` e o ruído do PostgREST não
/// dizem nada a quem está a usar o ecrã, e uma linha inteira de stack estoura o
/// espaço disponível.
String descreverErro(Object erro) {
  var texto = erro.toString().replaceFirst(RegExp(r'^\w*Exception:\s*'), '').trim();
  if (texto.length > 160) texto = '${texto.substring(0, 160)}…';
  return texto;
}
