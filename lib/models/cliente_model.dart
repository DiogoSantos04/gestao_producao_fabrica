import 'encomenda_model.dart';
import 'pedido_model.dart';

/// Cliente da fábrica.
///
/// Substitui o acesso por `Map` no ecrã de clientes, que dependia de quatro
/// helpers defensivos (`_obterTotalEncomendas`, `_temEncomendas`,
/// `_obterListaEncomendas`, `_obterListaPedidos`) para desembrulhar as junções.
/// Essa lógica passou para as fábricas dos modelos.
class ClienteModel {
  final int id;
  final String nomeCliente;
  final String? contacto;
  final String? email;
  final String? nif;
  final String? pessoaContacto;
  final String? morada;
  final bool ativo;

  /// Conta de utilizador associada, quando existe.
  /// Ligação introduzida para corrigir o bug (f) — ver BUGS_RESOLVIDOS.md.
  final String? utilizadorId;

  /// Histórico associado, quando a query o trouxe.
  final List<EncomendaModel> encomendas;
  final List<PedidoModel> pedidos;

  const ClienteModel({
    required this.id,
    this.nomeCliente = '',
    this.contacto,
    this.email,
    this.nif,
    this.pessoaContacto,
    this.morada,
    this.ativo = false,
    this.utilizadorId,
    this.encomendas = const [],
    this.pedidos = const [],
  });

  factory ClienteModel.fromJson(Map<String, dynamic> json) {
    return ClienteModel(
      id: (json['id'] as num).toInt(),
      nomeCliente: (json['nome_cliente'] as String?) ?? '',
      contacto: json['contacto'] as String?,
      email: json['email'] as String?,
      nif: json['nif'] as String?,
      pessoaContacto: json['pessoa_contacto'] as String?,
      morada: json['morada'] as String?,
      ativo: json['ativo'] == true,
      utilizadorId: json['utilizador_id'] as String?,
      encomendas: _lista(json['encomendas']).map(EncomendaModel.fromJson).toList(),
      pedidos: _lista(json['pedidos_encomenda']).map(PedidoModel.fromJson).toList(),
    );
  }

  int get totalEncomendas => encomendas.length;
  bool get temEncomendas => encomendas.isNotEmpty;

  /// Contacto telefónico formatado em grupos de 3 dígitos (ex: `+351 912 345 678`).
  ///
  /// A formatação vivia no ecrã, duplicada com o `TelefoneInputFormatter`.
  String get contactoFormatado {
    final limpo = (contacto ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (limpo.isEmpty) return 'Sem contacto';
    return formatarTelefone(limpo);
  }

  /// Corresponde ao termo de pesquisa em qualquer um dos campos textuais.
  bool corresponde(String termo) {
    if (termo.isEmpty) return true;
    final t = termo.toLowerCase();
    bool contem(String? v) => (v ?? '').toLowerCase().contains(t);
    return contem(nomeCliente) ||
        contem(email) ||
        contem(contacto) ||
        contem(nif) ||
        contem(pessoaContacto) ||
        contem(morada);
  }

  /// Insere espaços a cada 3 dígitos, preservando um `+` inicial.
  ///
  /// Partilhado com o formatador de input do ecrã, para que o texto escrito e o
  /// texto apresentado sigam exatamente a mesma regra.
  static String formatarTelefone(String valor) {
    final sb = StringBuffer();
    int digitos = 0;

    for (int i = 0; i < valor.length; i++) {
      final char = valor[i];
      if (char == '+' && i == 0) {
        sb.write(char);
        continue;
      }
      if (RegExp(r'\d').hasMatch(char)) {
        if (digitos == 3 || digitos == 6 || digitos == 9) sb.write(' ');
        sb.write(char);
        digitos++;
      }
    }
    return sb.toString();
  }

  static List<Map<String, dynamic>> _lista(dynamic v) {
    if (v is List) {
      return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}
