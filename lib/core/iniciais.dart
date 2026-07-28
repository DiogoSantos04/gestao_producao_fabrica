import 'package:flutter/material.dart';
import 'temas_cores.dart';

/// Converte um nome nas suas iniciais (ex: "Diogo Santos" -> "DS").
///
/// [omissao] é devolvido quando o nome está vazio ou é nulo.
/// [letrasNomeUnico] é o número de letras usadas quando o nome tem uma só
/// palavra. Com [usarUltimoNome] a segunda inicial vem do apelido em vez da
/// segunda palavra (relevante apenas em nomes com três ou mais palavras).
String obterIniciais(
  String? nome, {
  required String omissao,
  int letrasNomeUnico = 2,
  bool usarUltimoNome = false,
}) {
  final String limpo = nome?.trim() ?? '';
  if (limpo.isEmpty) return omissao;

  final partes = limpo.split(RegExp(r'\s+'));
  if (partes.length >= 2) {
    final segunda = usarUltimoNome ? partes.last : partes[1];
    return '${partes.first[0]}${segunda[0]}'.toUpperCase();
  }

  final letras = limpo.length >= letrasNomeUnico ? letrasNomeUnico : 1;
  return limpo.substring(0, letras).toUpperCase();
}

/// Paleta usada para colorir avatares de forma determinística.
/// Vive em [TemasCores.paletaAvatares], com as restantes cores da aplicação.
const _coresAvatar = TemasCores.paletaAvatares;

/// Cor estável para o avatar de [nome] — o mesmo nome dá sempre a mesma cor.
Color corAvatar(String nome) => _coresAvatar[nome.hashCode.abs() % _coresAvatar.length];
