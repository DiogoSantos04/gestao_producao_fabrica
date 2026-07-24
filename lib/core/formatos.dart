/// Formatações partilhadas pelos vários ecrãs.
///
/// Existia a mesma expressão copiada em quatro ficheiros, todas com o ano
/// fixo em 2026 — as ordens criadas noutro ano apareciam com a referência errada.
abstract class Formatos {
  /// Referência legível de uma ordem de produção: `ORD-<ano>-<id>`.
  ///
  /// O ano vem da data de criação da encomenda; se não estiver disponível,
  /// recorre-se ao ano corrente em vez de um valor fixo.
  static String referenciaOrdem(dynamic id, {dynamic criadaEm}) {
    final ano = DateTime.tryParse(criadaEm?.toString() ?? '')?.year ?? DateTime.now().year;
    return 'ORD-$ano-${id.toString().padLeft(3, '0')}';
  }

  /// Data e hora no formato `dd/mm/aaaa às hh:mm`, em hora local.
  static String dataHora(dynamic iso, {String vazio = 'N/A'}) {
    if (iso == null || iso.toString().isEmpty) return vazio;
    final dt = DateTime.tryParse(iso.toString())?.toLocal();
    if (dt == null) return iso.toString();
    String d2(int n) => n.toString().padLeft(2, '0');
    return '${d2(dt.day)}/${d2(dt.month)}/${dt.year} às ${d2(dt.hour)}:${d2(dt.minute)}';
  }
}
