import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ecra_recarregavel.dart';
import '../../core/paginacao.dart';
import '../../models/encomenda_model.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../services/pdf_service.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensagem), backgroundColor: Colors.red),
      );
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
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
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
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final estrelaIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          estrelaIndex <= notaSelecionada ? Icons.star_rounded : Icons.star_border_rounded,
                          color: Colors.amber,
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Agradecemos a sua avaliação! ⭐'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _carregarHistorico();
                          } on RepositoryException catch (e) {
                            setDialogState(() => enviando = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.mensagem), backgroundColor: Colors.red),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                  child: enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
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
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Consulte todas as suas encomendas, avalie a qualidade, repita um pedido ou baixe o certificado.',
                              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
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
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 12),
            Text(
              _erro!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _carregarHistorico,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_encomendas.isEmpty) {
      return const Center(
        child: Text('Ainda não tem encomendas registadas.', style: TextStyle(color: Colors.grey)),
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
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton.icon(
                onPressed: _carregarMais,
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

    final produto = enc.nomeProduto ?? 'Artigo';
    final jaAvaliado = _encomendasAvaliadasIds.contains(enc.id);

    final (Color corFundoBadge, Color corTextoBadge, Color corIcone, IconData icone) = switch (estado) {
      EstadoOrdem.concluida => (Colors.green.shade100, Colors.green.shade900, Colors.green, Icons.task_alt_rounded),
      EstadoOrdem.cancelada => (Colors.red.shade100, Colors.red.shade900, Colors.red, Icons.cancel_outlined),
      EstadoOrdem.emHold => (Colors.orange.shade100, Colors.orange.shade900, Colors.orange, Icons.pause_circle_outline),
      EstadoOrdem.emProducao => (Colors.blue.shade100, Colors.blue.shade900, Colors.deepPurple, Icons.receipt_long),
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
            color: corFundoBadge.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(icone, color: corIcone, size: 24),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: corFundoBadge,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      estadoTexto,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: corTextoBadge),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Artigo: $produto (${enc.quantidade} unid.)',
                style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w500),
              ),
              Text(
                'Data de Entrega: ${_formatarData(enc.dataEntrega)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              if (eCancelada && (enc.motivoCancelamento ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Motivo: ${enc.motivoCancelamento}',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade700),
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
            icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
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
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                  SizedBox(width: 4),
                  Text('Avaliado', style: TextStyle(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _mostrarDialogoAvaliacao(enc),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber.shade900,
                side: BorderSide(color: Colors.amber.shade300),
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
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
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
