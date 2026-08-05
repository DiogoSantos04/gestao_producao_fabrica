import 'package:flutter/material.dart';
import '../../../core/temas_cores.dart';

/// Moldura exterior de um cartão de KPI.
enum MolduraKpi {
  /// `Card` com elevação e contorno, com variante de alerta.
  cartao,

  /// `Container` branco com contorno e sombra suave.
  contorno,

  /// Sem moldura — o KPI é desenhado dentro de outro contentor.
  nenhuma,
}

/// Constantes visuais de um [CartaoKpi] / [ItemKpiCompacto].
///
/// Cada ecrã tinha a sua própria variação de espaçamentos, tamanhos e sombras.
/// Em vez de as uniformizar (o que mudaria o aspeto), cada variação passou a
/// ser um preset nomeado, e a árvore de widgets é escrita uma única vez.
class EstiloKpi {
  const EstiloKpi({
    required this.moldura,
    required this.paddingExterior,
    required this.estiloTitulo,
    required this.estiloValor,
    this.estiloSubtitulo,
    this.corSombra,
    this.desfoqueSombra = 0,
    this.deslocamentoSombra = Offset.zero,
    this.paddingIcone = 12,
    this.tamanhoIcone = 24,
    this.opacidadeFundoIcone = 0.12,
    this.espacoTituloValor = 0,
    this.espacoValorSubtitulo = 0,
    this.espacoIconeTexto = 12,
    this.alinhamentoColuna = MainAxisAlignment.start,
    this.expandirTexto = true,
  });

  final MolduraKpi moldura;
  final EdgeInsets paddingExterior;
  final TextStyle estiloTitulo;
  final TextStyle estiloValor;
  final TextStyle? estiloSubtitulo;

  final Color? corSombra;
  final double desfoqueSombra;
  final Offset deslocamentoSombra;

  final double paddingIcone;
  final double tamanhoIcone;

  /// Opacidade aplicada à cor do ícone quando não é passado um fundo explícito.
  final double opacidadeFundoIcone;

  final double espacoTituloValor;
  final double espacoValorSubtitulo;
  final double espacoIconeTexto;

  final MainAxisAlignment alinhamentoColuna;

  /// Se o bloco de texto é envolvido num `Expanded`.
  final bool expandirTexto;

  /// Preset do dashboard principal: `Card` elevado, valor grande a preto.
  static const principal = EstiloKpi(
    moldura: MolduraKpi.cartao,
    paddingExterior: EdgeInsets.all(16),
    estiloTitulo: TextStyle(fontSize: 13, color: TemasCores.textoTerciario, fontWeight: FontWeight.w500),
    estiloValor: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
    estiloSubtitulo: TextStyle(fontSize: 11, color: TemasCores.textoDesativado),
    espacoTituloValor: 4,
    espacoValorSubtitulo: 4,
    alinhamentoColuna: MainAxisAlignment.center,
  );

  /// Preset das informações de clientes: contorno com sombra ténue.
  static const clientes = EstiloKpi(
    moldura: MolduraKpi.contorno,
    paddingExterior: EdgeInsets.all(20),
    estiloTitulo: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: TemasCores.textoApoio),
    estiloValor: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
    estiloSubtitulo: TextStyle(fontSize: 11, color: TemasCores.textoTerciario),
    corSombra: TemasCores.sombraTenue,
    desfoqueSombra: 6,
    deslocamentoSombra: Offset(0, 2),
    paddingIcone: 10,
    tamanhoIcone: 22,
    opacidadeFundoIcone: 0.08,
    espacoTituloValor: 6,
    espacoValorSubtitulo: 4,
  );

  /// Preset da gestão de utilizadores: ícone à esquerda, valor colorido.
  static const utilizadores = EstiloKpi(
    moldura: MolduraKpi.contorno,
    paddingExterior: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    estiloTitulo: TextStyle(fontSize: 12, color: TemasCores.textoTerciario, fontWeight: FontWeight.w500),
    estiloValor: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    corSombra: TemasCores.sombraSuave,
    desfoqueSombra: 10,
    deslocamentoSombra: Offset(0, 4),
    espacoValorSubtitulo: 2,
    espacoIconeTexto: 14,
  );

  /// Preset dos postos de trabalho: item solto dentro da barra de resumo.
  static const postos = EstiloKpi(
    moldura: MolduraKpi.nenhuma,
    paddingExterior: EdgeInsets.zero,
    estiloTitulo: TextStyle(fontSize: 11, color: TemasCores.textoTerciario, fontWeight: FontWeight.w500),
    estiloValor: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    paddingIcone: 10,
    tamanhoIcone: 22,
    espacoIconeTexto: 12,
    expandirTexto: false,
  );
}

/// Aplica a moldura exterior definida pelo [estilo].
Widget _comMoldura({
  required EstiloKpi estilo,
  required Widget filho,
  double? largura,
  bool alerta = false,
}) {
  switch (estilo.moldura) {
    case MolduraKpi.cartao:
      return Card(
        color: TemasCores.superficie,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: alerta ? TemasCores.erroBorda : TemasCores.borda,
            width: alerta ? 1.5 : 1,
          ),
        ),
        child: Padding(padding: estilo.paddingExterior, child: filho),
      );
    case MolduraKpi.contorno:
      return Container(
        width: largura,
        padding: estilo.paddingExterior,
        decoration: BoxDecoration(
          color: TemasCores.superficie,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TemasCores.borda),
          boxShadow: estilo.corSombra == null
              ? null
              : [
                  BoxShadow(
                    color: estilo.corSombra!,
                    blurRadius: estilo.desfoqueSombra,
                    offset: estilo.deslocamentoSombra,
                  ),
                ],
        ),
        child: filho,
      );
    case MolduraKpi.nenhuma:
      return filho;
  }
}

/// Caixa arredondada do ícone, comum a todos os cartões de KPI.
class _CaixaIcone extends StatelessWidget {
  const _CaixaIcone({
    required this.estilo,
    required this.icone,
    required this.cor,
    this.fundo,
  });

  final EstiloKpi estilo;
  final IconData icone;
  final Color cor;
  final Color? fundo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(estilo.paddingIcone),
      decoration: BoxDecoration(
        color: fundo ?? cor.withValues(alpha: estilo.opacidadeFundoIcone),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icone, color: cor, size: estilo.tamanhoIcone),
    );
  }
}

/// Cartão de KPI com o ícone à direita e título → valor → subtítulo.
class CartaoKpi extends StatelessWidget {
  const CartaoKpi({
    super.key,
    required this.estilo,
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.icone,
    required this.corIcone,
    this.fundoIcone,
    this.largura,
    this.alerta = false,
  });

  final EstiloKpi estilo;
  final String titulo;
  final String valor;
  final String subtitulo;
  final IconData icone;
  final Color corIcone;

  /// Fundo da caixa do ícone. Se nulo deriva de [corIcone].
  final Color? fundoIcone;
  final double? largura;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    return _comMoldura(
      estilo: estilo,
      largura: largura,
      alerta: alerta,
      filho: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: estilo.alinhamentoColuna,
              children: [
                Text(titulo, style: estilo.estiloTitulo),
                SizedBox(height: estilo.espacoTituloValor),
                Text(valor, style: estilo.estiloValor),
                SizedBox(height: estilo.espacoValorSubtitulo),
                Text(subtitulo, style: estilo.estiloSubtitulo),
              ],
            ),
          ),
          _CaixaIcone(estilo: estilo, icone: icone, cor: corIcone, fundo: fundoIcone),
        ],
      ),
    );
  }
}

/// KPI compacto com o ícone à esquerda e o valor colorido por cima do título.
class ItemKpiCompacto extends StatelessWidget {
  const ItemKpiCompacto({
    super.key,
    required this.estilo,
    required this.titulo,
    required this.valor,
    required this.icone,
    required this.cor,
  });

  final EstiloKpi estilo;
  final String titulo;
  final String valor;
  final IconData icone;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    final texto = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(valor, style: estilo.estiloValor.copyWith(color: cor)),
        SizedBox(height: estilo.espacoValorSubtitulo),
        Text(titulo, style: estilo.estiloTitulo),
      ],
    );

    return _comMoldura(
      estilo: estilo,
      filho: Row(
        children: [
          _CaixaIcone(estilo: estilo, icone: icone, cor: cor),
          SizedBox(width: estilo.espacoIconeTexto),
          if (estilo.expandirTexto) Expanded(child: texto) else texto,
        ],
      ),
    );
  }
}
