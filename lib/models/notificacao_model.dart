import 'package:flutter/material.dart';

import '../core/temas_cores.dart';

/// Transição de uma encomenda que gera aviso no portal.
///
/// A coluna `notificacoes.evento` é texto — e é nula nas notificações internas
/// anteriores a esta funcionalidade —, por isso o que não for reconhecido cai
/// em [EventoNotificacao.generico] em vez de rebentar.
enum EventoNotificacao {
  iniciada,
  concluida,
  cancelada,
  entregue,
  generico;

  static EventoNotificacao desdeTexto(String? valor) => switch (valor?.trim()) {
        'encomenda_iniciada' => EventoNotificacao.iniciada,
        'encomenda_concluida' => EventoNotificacao.concluida,
        'encomenda_cancelada' => EventoNotificacao.cancelada,
        'encomenda_entregue' => EventoNotificacao.entregue,
        _ => EventoNotificacao.generico,
      };

  IconData get icone => switch (this) {
        EventoNotificacao.iniciada => Icons.play_circle_outline_rounded,
        EventoNotificacao.concluida => Icons.check_circle_outline_rounded,
        EventoNotificacao.cancelada => Icons.cancel_outlined,
        EventoNotificacao.entregue => Icons.inventory_2_outlined,
        EventoNotificacao.generico => Icons.notifications_none_rounded,
      };

  /// Cor do ícone. Segue a mesma leitura do resto do portal: verde é fecho com
  /// sucesso, vermelho é cancelamento, roxo é o acento do cliente.
  Color get cor => switch (this) {
        EventoNotificacao.iniciada => TemasCores.clienteAcento,
        EventoNotificacao.concluida => TemasCores.sucesso,
        EventoNotificacao.cancelada => TemasCores.erro,
        EventoNotificacao.entregue => TemasCores.sucesso,
        EventoNotificacao.generico => TemasCores.textoApoio,
      };
}

/// Aviso mostrado ao cliente no sino do portal.
class NotificacaoModel {
  final Object id;
  final String titulo;
  final String mensagem;
  final bool lida;
  final DateTime? criadaEm;
  final EventoNotificacao evento;

  /// Código da encomenda a que o aviso diz respeito, quando existe.
  ///
  /// É o que torna a linha clicável: com ele, tocar na notificação abre o
  /// rastreio dessa ordem. Nulo nas notificações que não são de encomendas.
  final String? codigoRastreio;

  const NotificacaoModel({
    required this.id,
    required this.titulo,
    required this.mensagem,
    required this.lida,
    required this.evento,
    this.criadaEm,
    this.codigoRastreio,
  });

  factory NotificacaoModel.fromJson(Map<String, dynamic> json) {
    final codigo = json['codigo_rastreio']?.toString().trim();

    return NotificacaoModel(
      id: json['id'] as Object,
      titulo: json['titulo']?.toString() ?? '',
      mensagem: json['mensagem']?.toString() ?? '',
      lida: json['lida'] == true,
      evento: EventoNotificacao.desdeTexto(json['evento']?.toString()),
      criadaEm: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      codigoRastreio: (codigo == null || codigo.isEmpty) ? null : codigo,
    );
  }

  /// Idade do aviso em texto curto, para a lista não repetir datas completas.
  String get quandoRelativo {
    final data = criadaEm;
    if (data == null) return '';

    final diferenca = DateTime.now().difference(data.toLocal());
    if (diferenca.inMinutes < 1) return 'agora';
    if (diferenca.inMinutes < 60) return '${diferenca.inMinutes} min';
    if (diferenca.inHours < 24) return '${diferenca.inHours} h';
    if (diferenca.inDays < 7) return '${diferenca.inDays} d';

    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }
}
