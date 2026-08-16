import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../repositories/base_repository.dart';
import '../../../repositories/portal_cliente_repository.dart';

/// Entregas por confirmar, apresentadas ao cliente logo à entrada do portal.
///
/// Existe porque o pedido de confirmação vivia apenas no email enviado quando a
/// produção acabava: se esse email não chegasse — remetente por verificar,
/// spam, ou simplesmente ninguém o ler —, o cliente nunca sabia que lhe pediam
/// alguma coisa, e o indicador de entregas confirmadas ficava baixo sem que
/// isso dissesse nada sobre as entregas reais.
///
/// Não substitui o email; é o caminho que não depende de nada externo. Quem
/// entra no portal vê o pedido, e confirma sem procurar códigos de rastreio.
///
/// Sem nada pendente ocupa zero espaço: um painel vazio a dizer "não tem nada"
/// só empurraria para baixo o conteúdo que o cliente veio ver.
class PainelPorConfirmar extends StatefulWidget {
  const PainelPorConfirmar({super.key});

  @override
  State<PainelPorConfirmar> createState() => _PainelPorConfirmarState();
}

class _PainelPorConfirmarState extends State<PainelPorConfirmar> {
  final PortalClienteRepository _repositorio = PortalClienteRepository();

  List<EncomendaPorConfirmar> _pendentes = [];

  /// Encomenda a ser confirmada agora, para travar o duplo toque. O servidor
  /// recusa a segunda confirmação, mas o erro que devolveria é ruído.
  int? _aConfirmar;

  int? _clienteId;

  /// A lista está aberta por inteiro. Fechada, mostra [_maximoFechado] linhas.
  ///
  /// Um cliente com dezenas de entregas por confirmar — o caso normal quando
  /// esta funcionalidade entra numa base já em uso — empurraria o resto do
  /// ecrã para fora da vista se o painel abrisse sempre com tudo.
  bool _expandido = false;

  static const int _maximoFechado = 4;

  RealtimeChannel? _canal;
  Timer? _agendamento;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _agendamento?.cancel();
    final canal = _canal;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final clienteId = _clienteId ??
          (await _repositorio.obterClienteAutenticado())?.id;

      // Uma conta sem registo de cliente associado não tem encomendas para
      // confirmar. Não é erro — o painel apenas não se mostra.
      if (clienteId == null) return;

      final pendentes = await _repositorio.obterPorConfirmar(clienteId);
      if (!mounted) return;

      setState(() {
        _clienteId = clienteId;
        _pendentes = pendentes;
      });

      _ligarRealtime();
    } on RepositoryException catch (e) {
      // Falhar aqui não pode estragar o ecrã: o painel é um extra por cima do
      // rastreio, e o cliente continua a poder confirmar pelo código.
      debugPrint('Não foi possível carregar as entregas por confirmar: ${e.mensagem}');
    }
  }

  /// Uma encomenda que acaba de ser concluída aparece aqui sem o cliente ter de
  /// recarregar — é o mesmo canal que o rastreio usa para seguir a produção.
  void _ligarRealtime() {
    if (_canal != null) return;

    _canal = _repositorio.escutarAtividadeDoCliente(
      'portal-cliente-por-confirmar-${DateTime.now().microsecondsSinceEpoch}',
      () {
        _agendamento?.cancel();
        _agendamento = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _carregar();
        });
      },
    );
  }

  Future<void> _confirmar(EncomendaPorConfirmar enc) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar receção'),
        content: Text(
          'Confirma que recebeu a encomenda ${enc.codigoRastreio}?\n\n'
          'A data e hora ficam registadas e não podem ser alteradas depois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.sucessoForte,
              foregroundColor: TemasCores.textoInverso,
            ),
            child: const Text('Sim, recebi'),
          ),
        ],
      ),
    );

    if (confirmou != true || !mounted) return;

    setState(() => _aConfirmar = enc.id);

    try {
      await _repositorio.confirmarRececao(enc.id);
      if (!mounted) return;

      // A linha sai da lista sem esperar pela ida à rede seguinte: a operação
      // não tem volta, pelo que o estado local não pode ficar errado.
      setState(() {
        _pendentes = _pendentes.where((p) => p.id != enc.id).toList();
        _aConfirmar = null;
      });

      context.mostrarMensagem(
        'Receção da encomenda ${enc.codigoRastreio} confirmada. Obrigado!',
      );
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _aConfirmar = null);
      context.mostrarMensagem(e.mensagem, eErro: true);
    }
  }

  static String _data(DateTime d) {
    final l = d.toLocal();
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(l.day)}/${d2(l.month)}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_pendentes.isEmpty) return const SizedBox.shrink();

    final int total = _pendentes.length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TemasCores.sucessoBorda),
      ),
      color: TemasCores.sucessoFundo,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: TemasCores.sucessoForte,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        total == 1
                            ? 'Tem 1 encomenda por confirmar'
                            : 'Tem $total encomendas por confirmar',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: TemasCores.sucessoTexto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'A produção terminou. Quando receber, confirme aqui '
                        'para fecharmos o processo.',
                        style: TextStyle(
                          fontSize: 12,
                          color: TemasCores.sucessoTexto,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...(_expandido ? _pendentes : _pendentes.take(_maximoFechado))
                .map(_construirLinha),
            if (total > _maximoFechado)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expandido = !_expandido),
                  style: TextButton.styleFrom(
                    foregroundColor: TemasCores.sucessoTexto,
                  ),
                  icon: Icon(
                    _expandido
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _expandido
                        ? 'Mostrar menos'
                        : 'Mostrar as restantes ${total - _maximoFechado}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _construirLinha(EncomendaPorConfirmar enc) {
    final bool aConfirmarEsta = _aConfirmar == enc.id;

    final descricao = [
      if (enc.nomeProduto != null) enc.nomeProduto!,
      if (enc.quantidade != null) '${enc.quantidade} un.',
      if (enc.dataEntrega != null) 'Prevista: ${_data(enc.dataEntrega!)}',
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.sucessoBorda),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enc.codigoRastreio,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: TemasCores.textoPrimario,
                  ),
                ),
                if (descricao.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: const TextStyle(
                      fontSize: 12,
                      color: TemasCores.textoTerciario,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _aConfirmar != null ? null : () => _confirmar(enc),
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.sucessoForte,
              foregroundColor: TemasCores.textoInverso,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: aConfirmarEsta
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: TemasCores.textoInverso,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Já recebi'),
          ),
        ],
      ),
    );
  }
}
