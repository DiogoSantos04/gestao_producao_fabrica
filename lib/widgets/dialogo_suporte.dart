import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/mensagens.dart';
import '../core/temas_cores.dart';
import '../repositories/base_repository.dart';

/// Canal de contacto com o administrador — do lado do cliente e do operador.
///
/// O protótipo de alta fidelidade do portal cliente (Figura 20, "Estado da
/// Encomenda") previa um botão "Contactar Suporte" que nunca chegou à
/// implementação. Este diálogo é o ponto único desse canal, partilhado pelos
/// dois perfis: cada chamada passa o seu próprio [aoObterEmail] (o repositório
/// de cada perfil tem a sua própria cópia de `obter_email_suporte`, porque a
/// política de RLS de `utilizadores` só deixa cada um ler a sua própria linha),
/// mas o diálogo, o texto e o comportamento são os mesmos.
///
/// O endereço não está escrito no código: se a conta de administração mudar, o
/// portal e o terminal acompanham.
Future<void> mostrarDialogoSuporte(
  BuildContext context, {
  required Future<String?> Function() aoObterEmail,
  String titulo = 'Contactar Suporte',
  String descricao = 'A nossa equipa responde a dúvidas sobre encomendas, prazos e estado de fabrico.',
  String rotuloEmail = 'Email de Suporte',
  Color corAcento = TemasCores.clienteAcento,
  String? codigoRastreio,
  String? assunto,
}) {
  return showDialog(
    context: context,
    builder: (_) => _DialogoSuporte(
      aoObterEmail: aoObterEmail,
      titulo: titulo,
      descricao: descricao,
      rotuloEmail: rotuloEmail,
      corAcento: corAcento,
      codigoRastreio: codigoRastreio,
      assunto: assunto,
    ),
  );
}

class _DialogoSuporte extends StatefulWidget {
  const _DialogoSuporte({
    required this.aoObterEmail,
    required this.titulo,
    required this.descricao,
    required this.rotuloEmail,
    required this.corAcento,
    this.codigoRastreio,
    this.assunto,
  });

  final Future<String?> Function() aoObterEmail;
  final String titulo;
  final String descricao;
  final String rotuloEmail;
  final Color corAcento;
  final String? codigoRastreio;
  final String? assunto;

  @override
  State<_DialogoSuporte> createState() => _DialogoSuporteState();
}

class _DialogoSuporteState extends State<_DialogoSuporte> {
  String? _email;
  String? _erro;
  bool _aCarregar = true;

  @override
  void initState() {
    super.initState();
    _carregarContacto();
  }

  Future<void> _carregarContacto() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });

    try {
      final email = await widget.aoObterEmail();
      if (!mounted) return;
      setState(() {
        _email = (email != null && email.trim().isNotEmpty) ? email.trim() : null;
        _erro = _email == null ? 'Não há neste momento um contacto de suporte disponível.' : null;
        _aCarregar = false;
      });
    } on RepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _aCarregar = false;
      });
    }
  }

  String get _assuntoMensagem {
    if (widget.assunto != null && widget.assunto!.trim().isNotEmpty) {
      return widget.assunto!.trim();
    }
    final codigo = widget.codigoRastreio?.trim();
    if (codigo != null && codigo.isNotEmpty) return 'Suporte - Encomenda $codigo';
    return 'Suporte - Portal do Cliente';
  }

  String get _corpoMensagem {
    final codigo = widget.codigoRastreio?.trim();
    final referencia = (codigo != null && codigo.isNotEmpty)
        ? '\n\nCódigo de rastreio: $codigo'
        : '';
    return 'Bom dia,\n\nVenho por este meio pedir informação sobre:$referencia\n\n';
  }

  /// Abre o cliente de email do sistema com o pedido já preenchido.
  ///
  /// `Uri(queryParameters:)` codifica os espaços como `+`, que muitos clientes
  /// de email mostram literalmente no assunto; daí a `query` ser montada à mão
  /// com [Uri.encodeComponent].
  Future<void> _enviarEmail() async {
    final email = _email;
    if (email == null) return;

    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(_assuntoMensagem)}'
          '&body=${Uri.encodeComponent(_corpoMensagem)}',
    );

    bool aberto = false;
    try {
      aberto = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      aberto = false;
    }

    if (!mounted) return;
    if (aberto) {
      Navigator.of(context).pop();
      return;
    }

    // Sem cliente de email associado (comum no browser), copiar o endereço é
    // mais útil do que um erro seco: o contacto continua a chegar ao cliente.
    await _copiarEmail(
      aviso: 'Não foi possível abrir o email. O endereço foi copiado para a área de transferência.',
    );
  }

  Future<void> _copiarEmail({String? aviso}) async {
    final email = _email;
    if (email == null) return;

    await Clipboard.setData(ClipboardData(text: email));
    if (!mounted) return;
    context.mostrarMensagem(aviso ?? 'Endereço de suporte copiado.', eErro: aviso != null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.support_agent_outlined, color: widget.corAcento),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.titulo)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.descricao,
              style: const TextStyle(fontSize: 13, color: TemasCores.textoSecundario),
            ),
            const SizedBox(height: 18),
            if (_aCarregar)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_erro != null)
              _construirErro()
            else
              _construirContacto(),
            if (!_aCarregar && _erro == null && (widget.codigoRastreio?.trim().isNotEmpty ?? false)) ...[
              const SizedBox(height: 12),
              Text(
                'A mensagem já leva o código ${widget.codigoRastreio!.trim()} no assunto.',
                style: const TextStyle(fontSize: 11, color: TemasCores.textoTerciario),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
        if (_erro != null && !_aCarregar)
          ElevatedButton.icon(
            onPressed: _carregarContacto,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.corAcento,
              foregroundColor: TemasCores.textoInverso,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar novamente'),
          )
        else if (!_aCarregar)
          ElevatedButton.icon(
            onPressed: _enviarEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.corAcento,
              foregroundColor: TemasCores.textoInverso,
            ),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Enviar Email'),
          ),
      ],
    );
  }

  Widget _construirErro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TemasCores.erroFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.erroBorda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: TemasCores.erroForte),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _erro!,
              style: const TextStyle(fontSize: 12, color: TemasCores.erroForte),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirContacto() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.corAcento.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.email_outlined, size: 18, color: widget.corAcento),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.rotuloEmail,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: TemasCores.textoTerciario),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  _email!,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: TemasCores.textoPrimario),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar endereço',
            onPressed: _copiarEmail,
            icon: const Icon(Icons.copy_rounded, size: 18, color: TemasCores.textoTerciario),
          ),
        ],
      ),
    );
  }
}
