import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';
import 'cartao_kpi.dart';

/// Os quatro cartões de resumo da carteira de clientes.
///
/// Os valores vêm do servidor ([MetricasClientes]): contados sobre a lista
/// carregada, passariam a descrever o tamanho da página em vez do total da
/// carteira.
class KpisCarteiraClientes extends StatelessWidget {
  const KpisCarteiraClientes({super.key, required this.metricas});

  final MetricasClientes metricas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool eWide = constraints.maxWidth > 900;
        final double cardWidth =
            eWide ? (constraints.maxWidth - 48) / 4 : (constraints.maxWidth - 16) / 2;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            CartaoKpi(
              estilo: EstiloKpi.clientes,
              largura: cardWidth,
              titulo: 'Total de Clientes',
              valor: '${metricas.total}',
              subtitulo: 'Empresas registadas',
              icone: Icons.business_rounded,
              corIcone: TemasCores.marcaEscura,
            ),
            CartaoKpi(
              estilo: EstiloKpi.clientes,
              largura: cardWidth,
              titulo: 'Acesso ao Portal',
              valor: '${metricas.ativosPortal}',
              subtitulo: 'Contas ativas',
              icone: Icons.verified_user_outlined,
              corIcone: TemasCores.sucessoTexto,
            ),
            CartaoKpi(
              estilo: EstiloKpi.clientes,
              largura: cardWidth,
              titulo: 'Clientes c/ Encomendas',
              valor: '${metricas.comEncomendas}',
              subtitulo: 'Com histórico associado',
              icone: Icons.shopping_bag_outlined,
              corIcone: TemasCores.infoTexto,
            ),
            CartaoKpi(
              estilo: EstiloKpi.clientes,
              largura: cardWidth,
              titulo: 'Volume de Encomendas',
              valor: '${metricas.totalEncomendas}',
              subtitulo: 'Total acumulado',
              icone: Icons.inventory_2_outlined,
              corIcone: TemasCores.avisoTexto,
            ),
          ],
        );
      },
    );
  }
}
