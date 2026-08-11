import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';
import '../../../models/encomenda_model.dart';
import '../../../models/pedido_model.dart';

/// Painel lateral com a ficha completa do cliente: dados fiscais, pedidos
/// submetidos pelo portal B2B e ordens de produção já lançadas.
///
/// Tudo o que mostra vem do `ClienteModel` que o ecrã já tem carregado — não
/// faz consultas próprias.
class PainelDetalheCliente extends StatelessWidget {
  const PainelDetalheCliente({
    super.key,
    required this.cliente,
    required this.aoFechar,
  });

  final ClienteModel cliente;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TemasCores.superficie,
        boxShadow: [
          BoxShadow(color: TemasCores.sombraMarcada, blurRadius: 16, offset: Offset(-4, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cabecalho(cliente: cliente, aoFechar: aoFechar),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SeccaoFiscal(cliente: cliente),
                  const SizedBox(height: 28),
                  _SeccaoPedidos(pedidos: cliente.pedidos),
                  const SizedBox(height: 28),
                  _SeccaoEncomendas(encomendas: cliente.encomendas),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cabeçalho escuro com nome, NIF e estado do portal.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.cliente, required this.aoFechar});

  final ClienteModel cliente;
  final VoidCallback aoFechar;

  @override
  Widget build(BuildContext context) {
    final nif = cliente.nif ?? '';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: TemasCores.marcaEscura,
        border: Border(bottom: BorderSide(color: TemasCores.bordaEscura)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  cliente.nomeCliente.isNotEmpty ? cliente.nomeCliente : 'Cliente',
                  style: const TextStyle(
                      color: TemasCores.textoInverso, fontSize: 20, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: TemasCores.textoInversoAtenuado),
                onPressed: aoFechar,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (nif.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: TemasCores.realceSobreEscuroForte,
                      borderRadius: BorderRadius.circular(4)),
                  child: Text('NIF: $nif',
                      style: const TextStyle(
                          color: TemasCores.textoInversoAtenuado,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cliente.ativo ? TemasCores.sucessoTextoForte : TemasCores.erroTextoForte,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cliente.ativo ? 'Portal Ativo' : 'Portal Bloqueado',
                  style: const TextStyle(
                      color: TemasCores.textoInverso, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dados cadastrais, fiscais e logísticos.
class _SeccaoFiscal extends StatelessWidget {
  const _SeccaoFiscal({required this.cliente});

  final ClienteModel cliente;

  @override
  Widget build(BuildContext context) {
    final nif = cliente.nif ?? '';
    final email = cliente.email ?? '';
    final pessoa = cliente.pessoaContacto ?? '';
    final morada = cliente.morada ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Informações Fiscais e Logísticas',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: TemasCores.superficieTenue,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: TemasCores.borda),
          ),
          child: Column(
            children: [
              if (nif.isNotEmpty) ...[
                _LinhaDetalhe(icone: Icons.badge_outlined, titulo: 'NIF / NIPC', valor: nif),
                const Divider(height: 16),
              ],
              _LinhaDetalhe(
                  icone: Icons.email_outlined,
                  titulo: 'Email',
                  valor: email.isNotEmpty ? email : 'Não registado'),
              const Divider(height: 16),
              _LinhaDetalhe(
                  icone: Icons.phone_outlined,
                  titulo: 'Telefone',
                  valor: cliente.contactoFormatado),
              if (pessoa.isNotEmpty) ...[
                const Divider(height: 16),
                _LinhaDetalhe(
                    icone: Icons.person_outline_rounded, titulo: 'Interlocutor', valor: pessoa),
              ],
              if (morada.isNotEmpty) ...[
                const Divider(height: 16),
                _LinhaDetalhe(
                    icone: Icons.location_on_outlined, titulo: 'Morada Carga', valor: morada),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Pedidos submetidos pelo portal B2B.
class _SeccaoPedidos extends StatelessWidget {
  const _SeccaoPedidos({required this.pedidos});

  final List<PedidoModel> pedidos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSeccao(
          titulo: 'Pedidos da Aplicação B2B',
          contador: pedidos.length,
          fundoContador: TemasCores.infoFundo,
          corContador: TemasCores.infoTextoForte,
        ),
        const SizedBox(height: 12),
        if (pedidos.isEmpty)
          const _SeccaoVazia('Nenhum pedido submetido na app.')
        else
          Column(
            children: [
              for (final p in pedidos)
                _ItemSeccao(
                  titulo: p.nomeProduto ?? 'Produto',
                  subtitulo: 'Qtd: ${p.quantidade} unidades',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: TemasCores.avisoFundo, borderRadius: BorderRadius.circular(4)),
                    child: Text(p.estado.etiqueta,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: TemasCores.avisoTextoForte)),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Ordens de produção já lançadas para o cliente.
class _SeccaoEncomendas extends StatelessWidget {
  const _SeccaoEncomendas({required this.encomendas});

  final List<EncomendaModel> encomendas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSeccao(
          titulo: 'Ordens de Produção Lançadas',
          contador: encomendas.length,
          fundoContador: TemasCores.superficieSuave,
          corContador: TemasCores.textoApoioIntenso,
        ),
        const SizedBox(height: 12),
        if (encomendas.isEmpty)
          const _SeccaoVazia('Nenhuma ordem de produção associada.')
        else
          Column(
            children: [
              for (final e in encomendas)
                _ItemSeccao(
                  titulo: e.codigoRastreio ?? 'TRC-N/A',
                  subtitulo: '${e.nomeProduto ?? 'Produto'} • Qtd: ${e.quantidade}',
                  trailing: Text(
                    e.dataEntregaIso ?? '',
                    style: const TextStyle(
                        fontSize: 11,
                        color: TemasCores.textoTerciario,
                        fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _TituloSeccao extends StatelessWidget {
  const _TituloSeccao({
    required this.titulo,
    required this.contador,
    required this.fundoContador,
    required this.corContador,
  });

  final String titulo;
  final int contador;
  final Color fundoContador;
  final Color corContador;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(titulo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario)),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: fundoContador, borderRadius: BorderRadius.circular(10)),
          child: Text('$contador',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corContador)),
        ),
      ],
    );
  }
}

class _SeccaoVazia extends StatelessWidget {
  const _SeccaoVazia(this.mensagem);

  final String mensagem;

  @override
  Widget build(BuildContext context) {
    return Text(mensagem,
        style: const TextStyle(
            fontSize: 12, color: TemasCores.textoTerciario, fontStyle: FontStyle.italic));
  }
}

/// Cartão de item usado tanto pelos pedidos como pelas encomendas.
/// Antes existiam duas construções praticamente idênticas.
class _ItemSeccao extends StatelessWidget {
  const _ItemSeccao({
    required this.titulo,
    required this.subtitulo,
    required this.trailing,
  });

  final String titulo;
  final String subtitulo;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12, color: TemasCores.textoPrimario)),
                Text(subtitulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: TemasCores.textoApoio)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _LinhaDetalhe extends StatelessWidget {
  const _LinhaDetalhe({required this.icone, required this.titulo, required this.valor});

  final IconData icone;
  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 16, color: TemasCores.textoApoio),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(titulo,
              style: const TextStyle(
                  fontSize: 12, color: TemasCores.textoApoio, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: TemasCores.textoPrimario),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
