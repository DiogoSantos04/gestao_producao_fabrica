import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ecra_recarregavel.dart';
import '../../core/mensagens.dart';
import '../../core/paginacao.dart';
import '../../core/temas_cores.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../services/pdf_service.dart';
import '../../widgets/etiqueta_estado.dart';

/// Histórico de encomendas do cliente autenticado.
class HistoricoClienteScreen extends StatefulWidget {
  /// Chamado quando o cliente pede a repetição de uma encomenda.
  ///
  /// O identificador do artigo viaja como `int`, o mesmo tipo que tem na base de
  /// dados: a conversão para `String` a meio do caminho não servia nada.
  final void Function(int tipoProdutoId, int quantidade)? onRepetirEncomenda;

  const HistoricoClienteScreen({super.key, this.onRepetirEncomenda});

  @override
  State<HistoricoClienteScreen> createState() => HistoricoClienteScreenState();
}

class HistoricoClienteScreenState extends State<HistoricoClienteScreen> implements EcraRecarregavel {
  final PortalClienteRepository _repositorio = PortalClienteRepository();

  List<EncomendaModel> _encomendas = [];
  Set<int> _encomendasAvaliadasIds = {};
  bool _temMais = false;
  bool _aCarregarMais = false;

  bool _isLoading = true;
  String? _erro;
  int? _clienteId;
  String _nomeCliente = 'Cliente';

  RealtimeChannel? _canal;
  Timer? _agendamentoRecarga;

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  @override
  void dispose() {
    _agendamentoRecarga?.cancel();
    final canal = _canal;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    super.dispose();
  }

  @override
  Future<void> recarregar() => _carregarHistorico();

  Future<void> _carregarHistorico() async {
    // O erro tem de ser limpo aqui: sem isto, uma única falha de rede deixava o
    // ecrã preso no estado de erro mesmo depois de recarregamentos bem
    // sucedidos — ver bug (D).
    if (mounted) {
      setState(() {
        _isLoading = true;
        _erro = null;
      });
    }

    try {
      // A identidade do cliente sai da chave estrangeira `clientes.utilizador_id`
      // e não da comparação de nomes que existia aqui — ver bug (A).
      final cliente = await _repositorio.obterClienteAutenticado();

      if (!mounted) return;
      if (cliente == null) {
        setState(() {
          _encomendas = [];
          _encomendasAvaliadasIds = {};
          _temMais = false;
          _clienteId = null;
          _erro = 'A sua conta ainda não está associada a um registo de cliente. '
              'Contacte-nos para concluir o registo.';
          _isLoading = false;
        });
        return;
      }

      _clienteId = cliente.id;
      _nomeCliente = cliente.nomeCliente;

      // Ao recarregar, repõe-se tudo o que já estava visível — e não apenas a
      // primeira página — para o cliente não perder o scroll que já tinha feito.
      final tamanho = _encomendas.length > tamanhoPaginaPadrao
          ? _encomendas.length
          : tamanhoPaginaPadrao;

      final pagina = await _repositorio.obterEncomendas(cliente.id, tamanho: tamanho);
      final avaliadas = await _repositorio.obterEncomendasAvaliadas(cliente.id);

      if (!mounted) return;
      setState(() {
        _encomendas = pagina.itens;
        _temMais = pagina.temMais;
        _encomendasAvaliadasIds = avaliadas;
        _isLoading = false;
      });

      _ligarRealtime();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _isLoading = false;
      });
    }
  }

  Future<void> _carregarMais() async {
    final clienteId = _clienteId;
    if (clienteId == null || _aCarregarMais || !_temMais) return;

    setState(() => _aCarregarMais = true);

    try {
      final pagina = await _repositorio.obterEncomendas(
        clienteId,
        deslocamento: _encomendas.length,
      );

      if (!mounted) return;
      setState(() {
        _encomendas = [..._encomendas, ...pagina.itens];
        _temMais = pagina.temMais;
        _aCarregarMais = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _aCarregarMais = false);
      context.mostrarMensagem(e.mensagem, eErro: true);
    }
  }

  /// Passa a acompanhar as mudanças de fase, conclusões e cancelamentos sem o
  /// cliente ter de carregar em recarregar.
  void _ligarRealtime() {
    if (_canal != null) return;

    _canal = _repositorio.escutarAtividadeDoCliente(
      'portal-cliente-historico-${_clienteId ?? 'sem-cliente'}',
      _agendarRecarga,
    );
  }

  /// Junta as alterações que chegam em rajada (o avanço de uma fase escreve em
  /// mais do que uma tabela) numa única leitura.
  void _agendarRecarga() {
    _agendamentoRecarga?.cancel();
    _agendamentoRecarga = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _carregarHistorico();
    });
  }

  void _mostrarDialogoAvaliacao(EncomendaModel enc) {
    final clienteId = _clienteId;
    if (clienteId == null) return;

    int notaSelecionada = 5;
    final comentarioController = TextEditingController();
    bool enviando = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.star_rounded, color: TemasCores.avaliacaoEstrela, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Avaliar ${enc.codigoRastreio ?? 'encomenda'}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Como avalia a qualidade de fabrico e o cumprimento do prazo?',
                    style: TextStyle(fontSize: 13, color: TemasCores.textoSecundario),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final estrelaIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          estrelaIndex <= notaSelecionada ? Icons.star_rounded : Icons.star_border_rounded,
                          color: TemasCores.avaliacaoEstrela,
                          size: 32,
                        ),
                        onPressed: () {
                          setDialogState(() => notaSelecionada = estrelaIndex);
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: comentarioController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comentário / Sugestão (opcional)',
                      border: OutlineInputBorder(),
                      hintText: 'Escreva a sua opinião sobre o produto entregue...',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: enviando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: enviando
                      ? null
                      : () async {
                          setDialogState(() => enviando = true);
                          try {
                            await _repositorio.registarAvaliacao(
                              encomendaId: enc.id,
                              clienteId: clienteId,
                              nota: notaSelecionada,
                              comentario: comentarioController.text,
                            );

                            if (!context.mounted) return;
                            Navigator.pop(context);
                            context.mostrarMensagem('Agradecemos a sua avaliação! ⭐');
                            _carregarHistorico();
                          } on RepositoryException catch (e) {
                            setDialogState(() => enviando = false);
                            if (!context.mounted) return;
                            context.mostrarMensagem(e.mensagem, eErro: true);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TemasCores.clienteAcento,
                    foregroundColor: TemasCores.textoInverso,
                  ),
                  child: enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
                        )
                      : const Text('Submeter Avaliação'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'A definir';
    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    // O portal é o módulo com maior probabilidade de ser aberto no telemóvel: o
    // `Padding(40)` fixo e a linha única de botões davam overflow em qualquer
    // ecrã estreito.
    final bool estreito = MediaQuery.of(context).size.width < 760;

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: TemasCores.clienteAcento))
          : Padding(
              padding: EdgeInsets.all(estreito ? 16.0 : 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Histórico de Encomendas',
                              style: TextStyle(
                                fontSize: estreito ? 22 : 28,
                                fontWeight: FontWeight.bold,
                                color: TemasCores.textoPrimarioFrio,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Consulte todas as suas encomendas, avalie a qualidade, repita um pedido ou baixe o certificado.',
                              style: TextStyle(fontSize: 14, color: TemasCores.textoSecundarioFrio),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        color: TemasCores.clienteAcento,
                        tooltip: 'Recarregar',
                        onPressed: _carregarHistorico,
                      ),
                    ],
                  ),
                  SizedBox(height: estreito ? 20 : 32),
                  Expanded(child: _construirCorpo(estreito)),
                ],
              ),
            ),
    );
  }

  Widget _construirCorpo(bool estreito) {
    if (_erro != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: TemasCores.erro, size: 40),
            const SizedBox(height: 12),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: TemasCores.erroTextoForte, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _carregarHistorico,
              style: OutlinedButton.styleFrom(foregroundColor: TemasCores.clienteAcento),
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_encomendas.isEmpty) {
      return const Center(
        child: Text('Ainda não tem encomendas registadas.', style: TextStyle(color: TemasCores.textoSecundarioFrio)),
      );
    }

    return ListView.builder(
      // Uma linha a mais para o botão de carregar mais, quando há mais páginas.
      itemCount: _encomendas.length + (_temMais ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _encomendas.length) return _construirBotaoCarregarMais();
        return _construirCartao(_encomendas[index], estreito);
      },
    );
  }

  Widget _construirBotaoCarregarMais() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      child: Center(
        child: _aCarregarMais
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.clienteAcento),
              )
            : OutlinedButton.icon(
                onPressed: _carregarMais,
                style: OutlinedButton.styleFrom(foregroundColor: TemasCores.clienteAcento),
                icon: const Icon(Icons.expand_more),
                label: const Text('Carregar mais encomendas'),
              ),
      ),
    );
  }

  Widget _construirCartao(EncomendaModel enc, bool estreito) {
    // Estado pela regra única: antes era adivinhado a partir do nome da fase
    // (`contains('concluí')`), o que dava por concluída uma ordem parada numa
    // fase chamada "Concluir montagem" e ignorava por completo as ordens
    // canceladas e suspensas — ver bug (B).
    final estado = enc.estado;
    final bool eConcluida = estado == EstadoOrdem.concluida;
    final bool eCancelada = estado == EstadoOrdem.cancelada;
    final cores = coresEstadoOrdem(estado);

    final produto = enc.nomeProduto ?? 'Artigo';
    final jaAvaliado = _encomendasAvaliadasIds.contains(enc.id);

    final IconData icone = switch (estado) {
      EstadoOrdem.concluida => Icons.task_alt_rounded,
      EstadoOrdem.cancelada => Icons.cancel_outlined,
      EstadoOrdem.emHold => Icons.pause_circle_outline,
      EstadoOrdem.emProducao => Icons.receipt_long,
    };

    // Em produção mostra-se a fase concreta; nos restantes estados a etiqueta do
    // próprio estado, que é a informação relevante para o cliente.
    final String estadoTexto = estado == EstadoOrdem.emProducao
        ? (enc.nomeFaseAtual?.toUpperCase() ?? EstadoOrdem.emProducao.etiqueta)
        : estado.etiqueta;

    final identificacao = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cores.fundo,
            shape: BoxShape.circle,
          ),
          child: Icon(icone, color: cores.texto, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    enc.codigoRastreio ?? 'Sem Código',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: TemasCores.textoApoioIntensoFrio),
                  ),
                  EtiquetaEstado.pilula(rotulo: estadoTexto, fundo: cores.fundo, texto: cores.texto),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Artigo: $produto (${enc.quantidade} unid.)',
                style: const TextStyle(color: TemasCores.textoApoioFrio, fontWeight: FontWeight.w500),
              ),
              Text(
                'Data de Entrega: ${_formatarData(enc.dataEntrega)}',
                style: const TextStyle(fontSize: 12, color: TemasCores.textoSecundarioFrio),
              ),
              if (eCancelada && (enc.motivoCancelamento ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Motivo: ${enc.motivoCancelamento}',
                    style: const TextStyle(fontSize: 12, color: TemasCores.erroTexto),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final acoes = Wrap(
      alignment: estreito ? WrapAlignment.start : WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        // O certificado atesta conformidade: só faz sentido numa ordem
        // efetivamente concluída, nunca numa cancelada.
        if (eConcluida) ...[
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: TemasCores.erroVivo),
            tooltip: 'Certificado de Conformidade PDF',
            onPressed: () {
              PdfService.descarregarCertificadoConformidade(
                codigoRastreio: enc.codigoRastreio ?? 'N/A',
                nomeCliente: _nomeCliente,
                nomeProduto: produto,
                quantidade: enc.quantidade,
                dataEntrega: _formatarData(enc.dataEntrega),
              );
            },
          ),
          if (jaAvaliado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TemasCores.avisoFundo,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, color: TemasCores.avaliacaoEstrela, size: 16),
                  SizedBox(width: 4),
                  Text('Avaliado', style: TextStyle(fontSize: 12, color: TemasCores.avisoTextoForte, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _mostrarDialogoAvaliacao(enc),
              style: OutlinedButton.styleFrom(
                foregroundColor: TemasCores.avisoTextoForte,
                side: const BorderSide(color: TemasCores.avisoBorda),
              ),
              icon: const Icon(Icons.star_outline_rounded, size: 18),
              label: const Text('Avaliar'),
            ),
        ],
        ElevatedButton.icon(
          onPressed: enc.tipoProdutoId == null
              ? null
              : () => widget.onRepetirEncomenda?.call(enc.tipoProdutoId!, enc.quantidade),
          style: ElevatedButton.styleFrom(
            backgroundColor: TemasCores.clienteAcento,
            foregroundColor: TemasCores.textoInverso,
          ),
          icon: const Icon(Icons.replay_rounded, size: 16),
          label: const Text('Repetir Pedido'),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: EdgeInsets.all(estreito ? 16 : 20),
        // Em ecrã estreito as ações descem para baixo da identificação, em vez
        // de disputarem a mesma linha e provocarem RenderFlex overflow.
        child: estreito
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identificacao,
                  const SizedBox(height: 12),
                  acoes,
                ],
              )
            : Row(
                children: [
                  Expanded(child: identificacao),
                  acoes,
                ],
              ),
      ),
    );
  }
}
