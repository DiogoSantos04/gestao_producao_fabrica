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
              flex: 1,
              child: _ColunaHistorico(cliente: cliente, aoAbrirDetalhe: aoAbrirDetalhe),
            ),
            Expanded(flex: 2, child: _ColunaAcessoPortal(ativo: cliente.ativo)),
            // O botão "Editar Dados" (ícone + texto + padding) não cabia no
            // `flex: 2` original assim que a tabela ficasse à largura mínima
            // do scroll horizontal — estourava à direita em toda a linha.
            Expanded(flex: 3, child: _ColunaAcoes(aoEditar: aoEditar)),
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
          Expanded(flex: 3, child: Text('Cliente & NIF', style: _estilo, overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 3,
              child: Text('Contacto / Interlocutor', style: _estilo, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 1, child: Text('Histórico', style: _estilo, overflow: TextOverflow.ellipsis)),
          Expanded(
              flex: 2,
              child: Text('Acesso ao Portal', style: _estilo, overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 3,
            child: Align(
                alignment: Alignment.centerRight,
                child: Text('Ações', style: _estilo, overflow: TextOverflow.ellipsis)),
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
              // O chip do NIF tem largura natural e não encolhia: entre 600 e
              // 700 px a tabela já não ganha o scroll horizontal (que só entra
              // abaixo de `ehCompacto`) e esta linha estourava 35 px à direita.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: TemasCores.borda,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'NIF $nif',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.bold, color: TemasCores.textoApoioIntenso),
                  ),
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
            // Um número de telefone formatado ocupa perto de 110 px e não parte
            // em lado nenhum: sem `Expanded`, a coluna estourava 98 px assim
            // que a tabela descia dos 700.
            Expanded(
              child: Text(
                cliente.contactoFormatado,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: TemasCores.textoApoioForte, fontSize: 13, fontWeight: FontWeight.w500),
              ),
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
        // `Flexible` no botão e no texto lá dentro: a coluna "Histórico" é a
        // mais estreita da tabela (flex 1), e "N encomendas" sem largura
        // finita para o `ellipsis` cortar estourava para fora da coluna.
        Flexible(
          child: InkWell(
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
                  Flexible(
                    child: Text(
                      '${cliente.totalEncomendas} encomendas',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: TemasCores.textoApoioForte, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
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
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: ativo ? TemasCores.estadoAtivoFundo : TemasCores.estadoInativoFundo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              ativo ? 'Ativo' : 'Inativo',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ativo ? TemasCores.textoInverso : TemasCores.textoSecundario,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
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
    // `Align` não limita a largura do filho — só a posição — pelo que o
    // botão, à largura natural do texto "Editar Dados", conseguia estourar
    // para fora da coluna. O `FittedBox` garante que encolhe em vez disso.
    return Align(
      alignment: Alignment.centerRight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
