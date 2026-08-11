import 'package:flutter/material.dart';

import '../core/temas_cores.dart';
import '../models/estado_ordem.dart';
import '../models/pedido_model.dart';

/// Cores do badge de estado de uma ordem de produção.
///
/// Cancelada é neutra — saiu da linha sem incidente; em hold é a urgente,
/// não a cancelada. Mesma regra usada em
/// `dashboard_admin/widgets/cartao_ordem_producao.dart`, centralizada aqui
/// para não voltar a divergir por ecrã (ver docs/BUGS_RESOLVIDOS.md, bug b).
({Color fundo, Color texto}) coresEstadoOrdem(EstadoOrdem estado) => switch (estado) {
      EstadoOrdem.cancelada => (fundo: TemasCores.superficieInerte, texto: TemasCores.inativoTexto),
      EstadoOrdem.emHold => (fundo: TemasCores.erroFundo, texto: TemasCores.erroTextoForte),
      EstadoOrdem.concluida => (fundo: TemasCores.sucessoFundo, texto: TemasCores.sucessoTextoForte),
      EstadoOrdem.emProducao => (fundo: TemasCores.infoFundo, texto: TemasCores.infoTextoForte),
    };

/// Cores do badge de estado de um pedido submetido pelo portal cliente.
({Color fundo, Color texto}) coresEstadoPedido(EstadoPedido estado) => switch (estado) {
      EstadoPedido.pendente => (fundo: TemasCores.avisoFundo, texto: TemasCores.avisoTextoForte),
      EstadoPedido.aprovado => (fundo: TemasCores.sucessoFundo, texto: TemasCores.sucessoTextoForte),
      EstadoPedido.emProducao => (fundo: TemasCores.infoFundo, texto: TemasCores.infoTextoForte),
      EstadoPedido.rejeitado => (fundo: TemasCores.erroFundo, texto: TemasCores.erroTextoForte),
    };

/// Etiqueta de estado: texto curto sobre um fundo colorido arredondado.
///
/// Os três construtores nomeados correspondem às métricas que já existiam nos
/// vários ecrãs — foram preservadas tal e qual para o aspeto não mudar.
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado({
    super.key,
    required this.rotulo,
    required this.fundo,
    required this.texto,
    required this.padding,
    required this.raio,
    required this.tamanhoLetra,
    this.borda,
  });

  /// Etiqueta miúda do painel de controlo (raio 4, letra 10).
  ///
  /// [paddingHorizontal] existe porque o badge do código de rastreio usava 6 e
  /// os restantes 8; a diferença é preservada para o aspeto não mudar.
  EtiquetaEstado.compacta({
    super.key,
    required this.rotulo,
    required this.fundo,
    required this.texto,
    this.borda,
    double paddingHorizontal = 8,
  })  : padding = EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: 2),
        raio = 4,
        tamanhoLetra = 10;

  /// Pílula da gestão de utilizadores (raio 12, letra 11).
  const EtiquetaEstado.pilula({
    super.key,
    required this.rotulo,
    required this.fundo,
    required this.texto,
    this.borda,
  })  : padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        raio = 12,
        tamanhoLetra = 11;

  /// Etiqueta grande dos pedidos de clientes (raio 20, letra 12).
  const EtiquetaEstado.destacada({
    super.key,
    required this.rotulo,
    required this.fundo,
    required this.texto,
    this.borda,
  })  : padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        raio = 20,
        tamanhoLetra = 12;

  final String rotulo;
  final Color fundo;
  final Color texto;
  final EdgeInsets padding;
  final double raio;
  final double tamanhoLetra;

  /// Contorno opcional; sem contorno quando nulo.
  final Color? borda;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(raio),
        border: borda == null ? null : Border.all(color: borda!),
      ),
      // Sem isto, quando o pai aperta a pílula (ex: coluna estreita de uma
      // tabela) o rótulo quebra a meio da palavra em vez de manter uma linha
      // só — a pílula é para ser lida de imediato, nunca em duas linhas.
      child: Text(
        rotulo,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: tamanhoLetra,
          fontWeight: FontWeight.bold,
          color: texto,
        ),
      ),
    );
  }
}
