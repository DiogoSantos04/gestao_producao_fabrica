import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/mensagens.dart';
import '../../core/temas_cores.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../widgets/etiqueta_estado.dart';

/// Consulta pública do estado de fabrico de uma encomenda.
///
/// O ecrã é acessível sem sessão iniciada (a partir do ecrã de login), pelo que
/// os dados vêm da função `rastrear_encomenda`, que devolve apenas o roteiro e o
/// estado. A consulta direta à tabela `encomendas` que existia aqui devolvia
/// também `clientes(nome_cliente)`: com códigos de formato enumerável, bastava
/// tentar códigos para descobrir que cliente encomendou o quê — ver bug (C).
class RastreioClienteScreen extends StatefulWidget {
  const RastreioClienteScreen({super.key});

  @override
  State<RastreioClienteScreen> createState() => _RastreioClienteScreenState();
}

class _RastreioClienteScreenState extends State<RastreioClienteScreen> {
  final PortalClienteRepository _repositorio = PortalClienteRepository();
  final _codigoController = TextEditingController();

  bool _isLoading = false;
  RastreioEncomenda? _encomenda;
  String? _erro;

  /// Código atualmente apresentado, usado para refazer a consulta quando a
  /// produção avança.
  String? _codigoEmCurso;

  RealtimeChannel? _canal;
  Timer? _agendamentoRecarga;

  bool _aContactarSuporte = false;

  @override
  void dispose() {
    _agendamentoRecarga?.cancel();
    final canal = _canal;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _buscarRastreio({bool silencioso = false}) async {
    final codigo = silencioso
        ? (_codigoEmCurso ?? '')
        : _codigoController.text.trim().toUpperCase();
    if (codigo.isEmpty) return;

    // Uma atualização vinda do realtime não deve apagar o cartão que o cliente
    // está a ver nem piscar o indicador de progresso.
    if (!silencioso) {
      setState(() {
        _isLoading = true;
        _encomenda = null;
        _erro = null;
      });
    }

    try {
      final resultado = await _repositorio.rastrear(codigo);

      // Cada `setState` a seguir a um `await` precisa da guarda: sair do
      // separador durante uma pesquisa lenta rebentava com
      // `setState() called after dispose()` — ver bug (E).
      if (!mounted) return;
      setState(() {
        _encomenda = resultado;
        _erro = resultado == null ? 'Nenhuma encomenda encontrada com o código informado.' : null;
        _isLoading = false;
        _codigoEmCurso = resultado == null ? null : codigo;
      });

      if (resultado != null) _ligarRealtime();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      // Uma falha na atualização automática não deve substituir por um erro o
      // cartão que o cliente já tem à frente.
      if (silencioso) {
        debugPrint('Falha ao atualizar o rastreio: ${e.mensagem}');
        return;
      }
      setState(() {
        _erro = e.mensagem;
        _isLoading = false;
      });
    }
  }

  /// Acompanha o avanço da produção sem o cliente ter de repetir a pesquisa.
  ///
  /// O ecrã prometia "tempo real" desde o início, mas só atualizava a pedido.
  void _ligarRealtime() {
    if (_canal != null) return;

    _canal = _repositorio.escutarAtividadeDoCliente(
      'portal-cliente-rastreio-${DateTime.now().microsecondsSinceEpoch}',
      _agendarRecarga,
    );
  }

  void _agendarRecarga() {
    _agendamentoRecarga?.cancel();
    _agendamentoRecarga = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _buscarRastreio(silencioso: true);
    });
  }

  /// Abre o email pré-preenchido para o administrador, com o código de
  /// rastreio no assunto — fecha o "Contactar Suporte" que o protótipo
  /// (Figura 20, "Estado da Encomenda") previa mas nunca chegou a implementar.
  Future<void> _contactarSuporte(RastreioEncomenda enc) async {
    if (_aContactarSuporte) return;
    setState(() => _aContactarSuporte = true);

    try {
      final email = await _repositorio.obterEmailSuporte();
      if (!mounted) return;

      if (email == null || email.isEmpty) {
        context.mostrarMensagem('Não foi possível obter o contacto de suporte.', eErro: true);
        return;
      }

      final uri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {
          'subject': 'Suporte - Encomenda ${enc.codigoRastreio.isEmpty ? '(sem código)' : enc.codigoRastreio}',
        },
      );

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else if (mounted) {
        context.mostrarMensagem('Não foi possível abrir o cliente de email.', eErro: true);
      }
    } on RepositoryException catch (e) {
      if (!mounted) return;
      context.mostrarMensagem(e.mensagem, eErro: true);
    } finally {
      if (mounted) setState(() => _aContactarSuporte = false);
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'A definir';
    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [TemasCores.clienteAcentoClaro, TemasCores.clienteAcentoForte],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.local_shipping_outlined, size: 34, color: TemasCores.textoInverso),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Rastreio de Encomendas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: TemasCores.textoPrimarioFrio),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Insira o código de rastreio para acompanhar o estado do seu pedido em tempo real.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: TemasCores.textoSecundarioFrio, fontSize: 14),
                ),
                const SizedBox(height: 28),

                // Card de Pesquisa
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: TemasCores.borda),
                  ),
                  color: TemasCores.superficie,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _codigoController,
                            decoration: const InputDecoration(
                              hintText: 'Código de Rastreio (Ex: TRC-XXXXXX)',
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search, color: TemasCores.textoTerciarioFrio),
                              contentPadding: EdgeInsets.symmetric(vertical: 14),
                            ),
                            textCapitalization: TextCapitalization.characters,
                            onSubmitted: (_) => _buscarRastreio(),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _buscarRastreio,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                            backgroundColor: TemasCores.clienteAcento,
                            foregroundColor: TemasCores.textoInverso,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                if (_isLoading) const Center(child: CircularProgressIndicator(color: TemasCores.clienteAcento)),

                if (_erro != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: TemasCores.erroFundo,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: TemasCores.erroBorda),
                    ),
                    child: Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: TemasCores.erroTextoForte, fontWeight: FontWeight.bold),
                    ),
                  ),

                if (_encomenda != null) _construirResultado(_encomenda!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _construirResultado(RastreioEncomenda enc) {
    // O estado sai da regra única de `EstadoOrdem`, e não do nome da fase: uma
    // encomenda cancelada ou suspensa aparecia antes como se estivesse a
    // avançar normalmente — ver bug (B).
    final estado = EstadoOrdem.derivar(
      cancelada: enc.cancelada,
      emSuspenso: enc.emSuspenso,
      temFaseAtual: enc.faseAtualId != null,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  enc.codigoRastreio.isEmpty ? 'Sem código' : enc.codigoRastreio,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemasCores.textoApoioIntensoFrio),
                ),
                EtiquetaEstado.destacada(
                  rotulo: enc.nomeProduto ?? 'Artigo',
                  fundo: TemasCores.clienteAcentoFundo,
                  texto: TemasCores.clienteAcentoForte,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _construirBadgeEstado(estado),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event, size: 16, color: TemasCores.textoSecundarioFrio),
                const SizedBox(width: 6),
                Text(
                  'Data Prevista de Entrega: ${_formatarData(enc.dataEntrega)}',
                  style: const TextStyle(color: TemasCores.textoSecundarioFrio, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Divider(height: 32, color: TemasCores.borda),
            const Text(
              'Etapas de Fabrico',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: TemasCores.textoPrimarioFrio),
            ),
            const SizedBox(height: 20),
            if (enc.faseAtualDesconhecida)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TemasCores.alertaFundo,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TemasCores.alertaBorda),
                  ),
                  child: const Text(
                    'A etapa em curso não consta do roteiro atual deste artigo. '
                    'O progresso detalhado não pode ser apresentado — contacte-nos para mais informação.',
                    style: TextStyle(fontSize: 12, color: TemasCores.alertaTextoForte),
                  ),
                ),
              ),
            if (enc.fases.isEmpty)
              const Text(
                'Ainda não há um roteiro de fabrico associado a este artigo.',
                style: TextStyle(fontSize: 13, color: TemasCores.textoSecundarioFrio),
              )
            else
              ...List.generate(enc.fases.length, (index) => _construirEtapa(enc, estado, index)),
            const Divider(height: 32, color: TemasCores.borda),
            OutlinedButton.icon(
              onPressed: _aContactarSuporte ? null : () => _contactarSuporte(enc),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: TemasCores.clienteAcento,
                side: const BorderSide(color: TemasCores.clienteAcentoClaro),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _aContactarSuporte
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.clienteAcento),
                    )
                  : const Icon(Icons.mail_outline_rounded, size: 18),
              label: const Text('Contactar Suporte'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirBadgeEstado(EstadoOrdem estado) {
    final cores = coresEstadoOrdem(estado);

    return EtiquetaEstado.destacada(
      rotulo: estado == EstadoOrdem.emHold ? 'PRODUÇÃO SUSPENSA' : estado.etiqueta,
      fundo: cores.fundo,
      texto: cores.texto,
    );
  }

  Widget _construirEtapa(RastreioEncomenda enc, EstadoOrdem estado, int index) {
    final fase = enc.fases[index];
    final indiceAtual = enc.indiceFaseAtual;
    final bool emHold = estado == EstadoOrdem.emHold;

    // Sem fase atual conhecida há dois casos distintos: a ordem percorreu o
    // roteiro todo (concluída) ou a fase gravada já não existe. Só o primeiro
    // justifica marcar as etapas como concluídas.
    final bool isConcluida = indiceAtual != null
        ? index < indiceAtual
        : (estado == EstadoOrdem.concluida && !enc.faseAtualDesconhecida);
    final bool isFaseAtual = indiceAtual != null && index == indiceAtual;

    final Color corIcone = isConcluida
        ? TemasCores.sucesso
        : isFaseAtual
            ? (emHold ? TemasCores.erro : TemasCores.clienteAcento)
            : TemasCores.textoTerciarioFrio;

    final String legenda = isConcluida
        ? 'Concluída'
        : isFaseAtual
            ? (emHold ? 'Suspensa' : 'Em Processamento')
            : 'Pendente';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              isConcluida
                  ? Icons.check_circle
                  : isFaseAtual
                      ? (emHold ? Icons.pause_circle_filled : Icons.play_circle_filled)
                      : Icons.radio_button_unchecked,
              color: corIcone,
              size: 22,
            ),
            if (index < enc.fases.length - 1)
              Container(
                width: 2,
                height: 36,
                color: isConcluida ? TemasCores.sucesso : TemasCores.borda,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fase.nome,
                style: TextStyle(
                  fontWeight: (isFaseAtual || isConcluida) ? FontWeight.bold : FontWeight.normal,
                  color: isFaseAtual
                      ? (emHold ? TemasCores.erroTextoForte : TemasCores.clienteAcentoForte)
                      : isConcluida
                          ? TemasCores.sucessoTextoForte
                          : TemasCores.textoSecundarioFrio,
                  fontSize: 14,
                ),
              ),
              Text(
                legenda,
                style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciarioFrio),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
