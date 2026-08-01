import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/estado_ordem.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';

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

  String _formatarData(DateTime? data) {
    if (data == null) return 'A definir';
    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Rastreio de Encomendas',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Insira o código de rastreio para acompanhar o estado do seu pedido em tempo real.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                ),
                const SizedBox(height: 28),

                // Card de Pesquisa
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  color: Colors.white,
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
                              prefixIcon: Icon(Icons.search, color: Color(0xFF94A3B8)),
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
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Icon(Icons.arrow_forward),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                if (_isLoading) const Center(child: CircularProgressIndicator()),

                if (_erro != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF1E293B)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    enc.nomeProduto ?? 'Artigo',
                    style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _construirBadgeEstado(estado),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event, size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  'Data Prevista de Entrega: ${_formatarData(enc.dataEntrega)}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              'Etapas de Fabrico',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 20),
            if (enc.faseAtualDesconhecida)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    'A etapa em curso não consta do roteiro atual deste artigo. '
                    'O progresso detalhado não pode ser apresentado — contacte-nos para mais informação.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
                  ),
                ),
              ),
            if (enc.fases.isEmpty)
              const Text(
                'Ainda não há um roteiro de fabrico associado a este artigo.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              )
            else
              ...List.generate(enc.fases.length, (index) => _construirEtapa(enc, estado, index)),
          ],
        ),
      ),
    );
  }

  Widget _construirBadgeEstado(EstadoOrdem estado) {
    final (Color fundo, Color texto) = switch (estado) {
      EstadoOrdem.cancelada => (Colors.red.shade50, Colors.red.shade900),
      EstadoOrdem.emHold => (Colors.orange.shade50, Colors.orange.shade900),
      EstadoOrdem.concluida => (Colors.green.shade50, Colors.green.shade900),
      EstadoOrdem.emProducao => (Colors.blue.shade50, Colors.blue.shade900),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: fundo, borderRadius: BorderRadius.circular(20)),
      child: Text(
        estado == EstadoOrdem.emHold ? 'PRODUÇÃO SUSPENSA' : estado.etiqueta,
        style: TextStyle(color: texto, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Widget _construirEtapa(RastreioEncomenda enc, EstadoOrdem estado, int index) {
    final fase = enc.fases[index];
    final indiceAtual = enc.indiceFaseAtual;

    // Sem fase atual conhecida há dois casos distintos: a ordem percorreu o
    // roteiro todo (concluída) ou a fase gravada já não existe. Só o primeiro
    // justifica marcar as etapas como concluídas.
    final bool isConcluida = indiceAtual != null
        ? index < indiceAtual
        : (estado == EstadoOrdem.concluida && !enc.faseAtualDesconhecida);
    final bool isFaseAtual = indiceAtual != null && index == indiceAtual;

    final Color corIcone = isConcluida
        ? Colors.green
        : isFaseAtual
            ? (estado == EstadoOrdem.emHold ? Colors.orange.shade700 : Colors.orange)
            : Colors.grey.shade300;

    final String legenda = isConcluida
        ? 'Concluída'
        : isFaseAtual
            ? (estado == EstadoOrdem.emHold ? 'Suspensa' : 'Em Processamento')
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
                      ? (estado == EstadoOrdem.emHold ? Icons.pause_circle_filled : Icons.play_circle_filled)
                      : Icons.radio_button_unchecked,
              color: corIcone,
              size: 22,
            ),
            if (index < enc.fases.length - 1)
              Container(
                width: 2,
                height: 36,
                color: isConcluida ? Colors.green : Colors.grey.shade200,
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
                      ? Colors.orange.shade800
                      : isConcluida
                          ? Colors.green.shade800
                          : const Color(0xFF64748B),
                  fontSize: 14,
                ),
              ),
              Text(
                legenda,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
