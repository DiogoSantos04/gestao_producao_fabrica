import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/cliente_model.dart';

/// Uma linha da tabela de clientes.
///
/// Cada coluna é um widget próprio: o método original tinha 191 linhas e não
/// havia forma de mexer numa coluna sem ler as outras quatro.
class LinhaCliente extends StatelessWidget {
  const LinhaCliente({
    super.key,
    required this.cliente,
    required this.aoAbrirDetalhe,
    required this.aoEditar,
  });

  final ClienteModel cliente;
  final VoidCallback aoAbrirDetalhe;
  final VoidCallback aoEditar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: aoAbrirDetalhe,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 3, child: _ColunaIdentificacao(cliente: cliente)),
            Expanded(flex: 3, child: _ColunaContacto(cliente: cliente)),
            Expanded(
              flex: 2,
              child: _ColunaHistorico(cliente: cliente, aoAbrirDetalhe: aoAbrirDetalhe),
            ),
            Expanded(flex: 2, child: _ColunaAcessoPortal(ativo: cliente.ativo)),
            Expanded(flex: 2, child: _ColunaAcoes(aoEditar: aoEditar)),
          ],
        ),
      ),
    );
  }
}

/// Cabeçalho da tabela de clientes. Não é ordenável: a ordem vem do servidor.
class CabecalhoTabelaClientes extends StatelessWidget {
  const CabecalhoTabelaClientes({super.key});

  static const _estilo = TextStyle(
      fontWeight: FontWeight.bold, color: TemasCores.textoTerciario, fontSize: 13);

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Cliente & NIF', style: _estilo)),
          Expanded(flex: 3, child: Text('Contacto / Interlocutor', style: _estilo)),
          Expanded(flex: 2, child: Text('Histórico', style: _estilo)),
          Expanded(flex: 2, child: Text('Acesso ao Portal', style: _estilo)),
          Expanded(
            flex: 2,
            child: Align(alignment: Alignment.centerRight, child: Text('Ações', style: _estilo)),
          ),
        ],
      ),
    );
  }
}

/// Coluna 1: nome da empresa, NIF, email e morada.
class _ColunaIdentificacao extends StatelessWidget {
  const _ColunaIdentificacao({required this.cliente});

  final ClienteModel cliente;

  @override
  Widget build(BuildContext context) {
    final nif = cliente.nif ?? '';
    final morada = cliente.morada ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cliente.nomeCliente.isNotEmpty ? cliente.nomeCliente : 'N/A',
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: TemasCores.textoPrimario, fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (nif.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: TemasCores.borda,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'NIF $nif',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: TemasCores.textoApoioIntenso),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.email_outlined, size: 12, color: TemasCores.textoDesativado),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                cliente.email ?? 'Sem email',
                style: const TextStyle(color: TemasCores.textoTerciario, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (morada.isNotEmpty) ...[
          const SizedBox(height: 3),
          LinhaIcone(icone: Icons.location_on_outlined, texto: morada, tamanho: 11),
        ],
      ],
    );
  }
}

/// Coluna 2: telefone e interlocutor.
class _ColunaContacto extends StatelessWidget {
  const _ColunaContacto({required this.cliente});

  final ClienteModel cliente;

  @override
  Widget build(BuildContext context) {
    final pessoa = cliente.pessoaContacto ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.phone_outlined, size: 14, color: TemasCores.textoDesativado),
            const SizedBox(width: 6),
            Text(
              cliente.contactoFormatado,
              style: const TextStyle(
                  color: TemasCores.textoApoioForte, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (pessoa.isNotEmpty) ...[
          const SizedBox(height: 4),
          LinhaIcone(
            icone: Icons.person_outline_rounded,
            texto: pessoa,
            tamanho: 12,
            peso: FontWeight.w500,
          ),
        ],
      ],
    );
  }
}

/// Coluna 3: total de encomendas, com atalho para o painel de detalhe.
class _ColunaHistorico extends StatelessWidget {
  const _ColunaHistorico({required this.cliente, required this.aoAbrirDetalhe});

  final ClienteModel cliente;
  final VoidCallback aoAbrirDetalhe;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: aoAbrirDetalhe,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: TemasCores.superficie,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: TemasCores.bordaForte),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history_toggle_off_rounded, size: 13, color: TemasCores.textoApoio),
                const SizedBox(width: 6),
                Text(
                  '${cliente.totalEncomendas} encomendas',
                  style: const TextStyle(
                      color: TemasCores.textoApoioForte, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Coluna 4: estado do acesso ao portal de rastreio.
class _ColunaAcessoPortal extends StatelessWidget {
  const _ColunaAcessoPortal({required this.ativo});

  final bool ativo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ativo ? TemasCores.estadoAtivoFundo : TemasCores.estadoInativoFundo,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            ativo ? 'Ativo' : 'Inativo',
            style: TextStyle(
              color: ativo ? TemasCores.textoInverso : TemasCores.textoSecundario,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// Coluna 5: ação de edição.
class _ColunaAcoes extends StatelessWidget {
  const _ColunaAcoes({required this.aoEditar});

  final VoidCallback aoEditar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: aoEditar,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: TemasCores.bordaForte),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        icon: const Icon(Icons.edit_outlined, size: 14, color: TemasCores.textoPrimario),
        label: const Text('Editar Dados',
            style: TextStyle(
                color: TemasCores.textoPrimario, fontSize: 12, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Linha compacta de ícone + texto, repetida nas colunas de identificação e contacto.
class LinhaIcone extends StatelessWidget {
  const LinhaIcone({
    super.key,
    required this.icone,
    required this.texto,
    this.tamanho = 12,
    this.peso = FontWeight.normal,
  });

  final IconData icone;
  final String texto;
  final double tamanho;
  final FontWeight peso;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 12, color: TemasCores.textoDesativado),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(color: TemasCores.textoTerciario, fontSize: tamanho, fontWeight: peso),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
