import 'package:flutter/material.dart';

/// Paleta em bruto: a **única** lista de valores hexadecimais da aplicação.
///
/// As rampas reproduzem exatamente os tons do Material (`Colors.grey.shade600`
/// e companhia) que estavam espalhados pelos ecrãs. Estão declaradas em
/// hexadecimal — e não como `Colors.x.shadeN` — porque os `shadeN` do Flutter
/// são *getters* e não podem ser usados em contexto `const`.
///
/// Nenhum ecrã deve ler daqui diretamente: usa-se [TemasCores], que dá nome ao
/// papel de cada tom. A paleta existe apenas para que mudar a identidade visual
/// seja mudar números neste ficheiro.
class Paleta {
  const Paleta._();

  // ── Neutros (equivalente a Colors.grey) ──
  static const Color neutro50 = Color(0xFFFAFAFA);
  static const Color neutro100 = Color(0xFFF5F5F5);
  static const Color neutro150 = Color(0xFFEAEAEA); // fora da rampa Material
  static const Color neutro200 = Color(0xFFEEEEEE);
  static const Color neutro300 = Color(0xFFE0E0E0);
  static const Color neutro400 = Color(0xFFBDBDBD);
  static const Color neutro500 = Color(0xFF9E9E9E);
  static const Color neutro600 = Color(0xFF757575);
  static const Color neutro650 = Color(0xFF707070); // fora da rampa Material
  static const Color neutro700 = Color(0xFF616161);
  static const Color neutro800 = Color(0xFF424242);
  static const Color neutro900 = Color(0xFF212121);

  // ── Azul (equivalente a Colors.blue) ──
  static const Color azul50 = Color(0xFFE3F2FD);
  static const Color azul100 = Color(0xFFBBDEFB);
  static const Color azul200 = Color(0xFF90CAF9);
  static const Color azul300 = Color(0xFF64B5F6);
  static const Color azul400 = Color(0xFF42A5F5);
  static const Color azul500 = Color(0xFF2196F3);
  static const Color azul600 = Color(0xFF1E88E5);
  static const Color azul700 = Color(0xFF1976D2);
  static const Color azul800 = Color(0xFF1565C0);
  static const Color azul900 = Color(0xFF0D47A1);

  // ── Verde (equivalente a Colors.green) ──
  static const Color verde50 = Color(0xFFE8F5E9);
  static const Color verde100 = Color(0xFFC8E6C9);
  static const Color verde200 = Color(0xFFA5D6A7);
  static const Color verde300 = Color(0xFF81C784);
  static const Color verde500 = Color(0xFF4CAF50);
  static const Color verde600 = Color(0xFF43A047);
  static const Color verde700 = Color(0xFF388E3C);
  static const Color verde800 = Color(0xFF2E7D32);
  static const Color verde900 = Color(0xFF1B5E20);

  // ── Vermelho (equivalente a Colors.red) ──
  static const Color vermelho50 = Color(0xFFFFEBEE);
  static const Color vermelho100 = Color(0xFFFFCDD2);
  static const Color vermelho200 = Color(0xFFEF9A9A);
  static const Color vermelho300 = Color(0xFFE57373);
  static const Color vermelho400 = Color(0xFFEF5350);
  static const Color vermelho500 = Color(0xFFF44336);
  static const Color vermelho600 = Color(0xFFE53935);
  static const Color vermelho700 = Color(0xFFD32F2F);
  static const Color vermelho800 = Color(0xFFC62828);
  static const Color vermelho900 = Color(0xFFB71C1C);

  /// Equivalente a `Colors.redAccent`.
  static const Color vermelhoVivo = Color(0xFFFF5252);

  // ── Âmbar (equivalente a Colors.amber) ──
  static const Color ambar50 = Color(0xFFFFF8E1);
  static const Color ambar300 = Color(0xFFFFD54F);
  static const Color ambar500 = Color(0xFFFFC107);
  static const Color ambar800 = Color(0xFFFF8F00);
  static const Color ambar900 = Color(0xFFFF6F00);

  // ── Laranja (equivalente a Colors.orange) ──
  static const Color laranja50 = Color(0xFFFFF3E0);
  static const Color laranja100 = Color(0xFFFFE0B2);
  static const Color laranja500 = Color(0xFFFF9800);
  static const Color laranja700 = Color(0xFFF57C00);
  static const Color laranja800 = Color(0xFFEF6C00);
  static const Color laranja900 = Color(0xFFE65100);

  // ── Restantes acentos pontuais ──
  static const Color roxo50 = Color(0xFFEDE7F6); // Colors.deepPurple.shade50
  static const Color roxo500 = Color(0xFF673AB7); // Colors.deepPurple
  static const Color roxo600 = Color(0xFF5E35B1); // Colors.deepPurple.shade600

  // ── Violeta: acento de marca do portal cliente ──
  // Fora da rampa Material (que só tinha deepPurple, mais frio e menos saturado).
  static const Color violeta50 = Color(0xFFF1EFFE);
  static const Color violeta100 = Color(0xFFE3DFFC);
  static const Color violeta400 = Color(0xFF8F7FF7);
  static const Color violeta500 = Color(0xFF6C5CE7);
  static const Color violeta600 = Color(0xFF5B4BD6);
  static const Color violeta700 = Color(0xFF4C3FC0);
  static const Color indigo500 = Color(0xFF3F51B5); // Colors.indigo
  static const Color turquesa500 = Color(0xFF009688); // Colors.teal
  static const Color laranjaEscuro500 = Color(0xFFFF5722); // Colors.deepOrange
  static const Color purpura500 = Color(0xFF9C27B0); // Colors.purple
  static const Color castanho500 = Color(0xFF795548); // Colors.brown

  // ── Azul-acinzentado (equivalente a Colors.blueGrey) ──
  static const Color azulAcinzentado50 = Color(0xFFECEFF1);
  static const Color azulAcinzentado100 = Color(0xFFCFD8DC);
  static const Color azulAcinzentado500 = Color(0xFF607D8B);
  static const Color azulAcinzentado800 = Color(0xFF37474F);
  static const Color azulAcinzentado900 = Color(0xFF263238);

  // ── Ardósia: neutros frios usados nos ecrãs de relatórios/postos/portal cliente ──
  static const Color ardosia50 = Color(0xFFF8FAFC);
  static const Color ardosia400 = Color(0xFF94A3B8);
  static const Color ardosia500 = Color(0xFF64748B);
  static const Color ardosia600 = Color(0xFF475569);
  static const Color ardosia700 = Color(0xFF334155);
  static const Color ardosia800 = Color(0xFF1E293B);
  static const Color ardosia900 = Color(0xFF0F172A);

  // ── Absolutos e transparências ──
  static const Color branco = Color(0xFFFFFFFF);
  static const Color preto = Color(0xFF000000);
  static const Color preto87 = Color(0xDD000000);
  static const Color preto54 = Color(0x8A000000);
  static const Color preto26 = Color(0x42000000);
  static const Color preto08 = Color(0x08000000);
  static const Color preto05 = Color(0x05000000);
  static const Color branco70 = Color(0xB3FFFFFF);
  static const Color branco12 = Color(0x1FFFFFFF);
  static const Color branco10 = Color(0x1AFFFFFF);
}

/// Cores da aplicação, nomeadas pelo papel que desempenham.
///
/// Os ecrãs referem-se sempre a estes nomes, nunca a hexadecimais nem a
/// `Colors.x.shadeN`. Trocar a identidade visual é trocar o que estes nomes
/// apontam — não é procurar cores em centenas de sítios.
class TemasCores {
  const TemasCores._();

  // ───────────────────────── Marca ─────────────────────────

  /// Tom escuro da marca: fundo da barra lateral e realce forte (botão
  /// principal de relatórios, barras de progresso, breadcrumbs).
  static const Color marcaEscura = Color(0xFF111625);

  /// Cor de destaque da marca (item selecionado, ícones de cabeçalho, ações).
  static const Color marcaAcento = Paleta.azul500;

  /// Fundo do botão de ação principal (preto sólido).
  static const Color acaoPrincipal = Paleta.preto;

  /// Cor principal do tema Material (usada no login e no registo).
  static const Color primariaRoxa = Paleta.roxo500;

  /// Fundo alternativo de barra lateral mantido por compatibilidade.
  static const Color fundoEscuroSidebar = Color(0xFF1E1E2C);

  // ─────────────────────── Superfícies ───────────────────────

  /// Fundo geral de um ecrã.
  static const Color fundoEcra = Paleta.neutro50;

  /// Fundo de ecrã em tom frio (relatórios, postos de trabalho).
  static const Color fundoEcraFrio = Paleta.ardosia50;

  /// Fundo de um cartão, tabela ou diálogo.
  static const Color superficie = Paleta.branco;

  /// Fundo de zonas secundárias dentro de uma superfície (cabeçalhos de
  /// tabela, campos informativos, linhas alternadas).
  static const Color superficieSuave = Paleta.neutro100;

  /// Fundo de zonas secundárias muito ténues.
  static const Color superficieTenue = Paleta.neutro50;

  /// Pequeno destaque escuro sobre superfície clara (número da fase, chips).
  static const Color superficieEscura = Paleta.preto87;

  /// Fundo de elementos desativados ou inertes.
  static const Color superficieInerte = Paleta.neutro200;

  // ───────────────────────── Contornos ─────────────────────────

  /// Contorno normal de cartões, tabelas e campos.
  static const Color borda = Paleta.neutro200;

  /// Contorno mais marcado (separadores, campos com foco neutro).
  static const Color bordaForte = Paleta.neutro300;

  /// Contorno de contraste médio, para cinzas ligeiramente mais escuros.
  static const Color bordaNeutra = Paleta.neutro400;

  /// Contorno escuro, usado sobre superfícies de marca.
  static const Color bordaEscura = Paleta.neutro800;

  /// Véu que escurece o fundo por trás de um modal ou painel lateral.
  static const Color veuModal = Paleta.preto54;

  /// Sombra ténue de cartões com contorno.
  static const Color sombraTenue = Paleta.preto05;

  /// Sombra suave de cartões elevados.
  static const Color sombraSuave = Paleta.preto08;

  /// Sombra marcada (menus, sobreposições).
  static const Color sombraMarcada = Paleta.preto26;

  /// Cor base das sombras, para quando a opacidade é calculada no sítio.
  static const Color sombraBase = Paleta.preto;

  // ─────────────────────────── Texto ───────────────────────────

  /// Texto principal sobre fundo claro.
  static const Color textoPrimario = Paleta.preto87;

  /// Texto de apoio sobre fundo claro.
  static const Color textoSecundario = Paleta.preto54;

  /// Texto de menor importância (legendas, unidades, placeholders).
  static const Color textoTerciario = Paleta.neutro500;

  /// Texto desativado ou meramente decorativo.
  static const Color textoDesativado = Paleta.neutro400;

  /// Texto de apoio em cinzento neutro (legendas de gráficos, metadados).
  static const Color textoApoio = Paleta.neutro600;

  /// Texto de apoio com mais contraste (rótulos de formulário, cabeçalhos).
  static const Color textoApoioForte = Paleta.neutro700;

  /// Texto de apoio com o contraste máximo da escala neutra.
  static const Color textoApoioIntenso = Paleta.neutro800;

  /// Título de ecrã em tom frio (ecrãs com [fundoEcraFrio]).
  static const Color textoPrimarioFrio = Paleta.ardosia900;

  /// Texto de apoio em tom frio (ecrãs com [fundoEcraFrio]).
  static const Color textoSecundarioFrio = Paleta.ardosia500;

  /// Texto terciário em tom frio: placeholders, ícones ténues, legendas.
  static const Color textoTerciarioFrio = Paleta.ardosia400;

  /// Texto de apoio em tom frio, com mais peso (valores de campos, subtítulos).
  static const Color textoApoioFrio = Paleta.ardosia600;

  /// Texto de apoio em tom frio, de maior contraste (rótulos de formulário).
  static const Color textoApoioForteFrio = Paleta.ardosia700;

  /// Texto em tom frio de contraste máximo (códigos, títulos secundários).
  static const Color textoApoioIntensoFrio = Paleta.ardosia800;

  /// Texto sobre fundos escuros ou coloridos.
  static const Color textoInverso = Paleta.branco;

  /// Texto secundário sobre fundos escuros.
  static const Color textoInversoSuave = Paleta.neutro400;

  /// Texto terciário sobre fundos escuros.
  static const Color textoInversoTenue = Paleta.neutro500;

  /// Realce de item selecionado sobre fundo escuro.
  static const Color realceSobreEscuro = Color(0x14FFFFFF);

  /// Texto claro sobre fundos escuros, com mais presença que [textoInversoSuave].
  static const Color textoInversoClaro = Paleta.neutro300;

  /// Texto atenuado sobre fundos escuros (subtítulos do painel de detalhe).
  static const Color textoInversoAtenuado = Paleta.branco70;

  /// Realce mais marcado sobre fundo escuro (etiquetas dentro do cabeçalho).
  static const Color realceSobreEscuroForte = Paleta.branco12;

  /// Separador sobre fundo escuro.
  static const Color separadorEscuro = Paleta.branco10;

  // ────────────────────── Estados semânticos ──────────────────────
  // Cada estado segue sempre a mesma escala de papéis, do mais claro para o
  // mais escuro:
  //
  //   Fundo        tinta muito clara, para preencher etiquetas e caixas
  //   FundoForte   tinta clara, quando é preciso mais presença
  //   Borda        contorno da etiqueta ou da caixa
  //   Claro/Medio  variantes decorativas (barras, ícones ténues)
  //   <base>       a cor cheia do estado (ícones, botões, pontos)
  //   Forte        cor cheia mais escura (ícones sobre fundo claro)
  //   Texto        tom legível sobre `Fundo`
  //   TextoForte   /  TextoIntenso  tons progressivamente mais escuros

  /// Sucesso / concluído / ativo.
  static const Color sucesso = Paleta.verde500;
  static const Color sucessoFundo = Paleta.verde50;
  static const Color sucessoFundoForte = Paleta.verde100;
  static const Color sucessoBorda = Paleta.verde200;
  static const Color sucessoClaro = Paleta.verde300;
  static const Color sucessoForte = Paleta.verde600;
  static const Color sucessoTexto = Paleta.verde700;
  static const Color sucessoTextoForte = Paleta.verde800;
  static const Color sucessoTextoIntenso = Paleta.verde900;

  /// Erro / cancelado / crítico.
  static const Color erro = Paleta.vermelho500;
  static const Color erroFundo = Paleta.vermelho50;
  static const Color erroFundoForte = Paleta.vermelho100;
  static const Color erroBorda = Paleta.vermelho200;
  static const Color erroClaro = Paleta.vermelho300;
  static const Color erroMedio = Paleta.vermelho400;
  static const Color erroVivo = Paleta.vermelhoVivo;
  static const Color erroForte = Paleta.vermelho600;
  static const Color erroTexto = Paleta.vermelho700;
  static const Color erroTextoForte = Paleta.vermelho800;
  static const Color erroTextoIntenso = Paleta.vermelho900;

  /// Aviso / atraso / pendente.
  static const Color aviso = Paleta.ambar500;
  static const Color avisoFundo = Paleta.ambar50;
  static const Color avisoBorda = Paleta.ambar300;
  static const Color avisoTexto = Paleta.ambar800;
  static const Color avisoTextoForte = Paleta.ambar900;

  /// Alerta laranja (variante mais quente do aviso).
  static const Color alerta = Paleta.laranja500;
  static const Color alertaFundo = Paleta.laranja50;
  static const Color alertaFundoForte = Paleta.laranja100;
  static const Color alertaBorda = Paleta.laranja100;
  static const Color alertaMedio = Paleta.laranja700;
  static const Color alertaTexto = Paleta.laranja800;
  static const Color alertaTextoForte = Paleta.laranja900;

  /// Informação / em curso / neutro-positivo.
  static const Color info = Paleta.azul500;
  static const Color infoFundo = Paleta.azul50;
  static const Color infoFundoForte = Paleta.azul100;
  static const Color infoBorda = Paleta.azul200;
  static const Color infoClaro = Paleta.azul300;
  static const Color infoMedio = Paleta.azul400;
  static const Color infoForte = Paleta.azul600;
  static const Color infoTexto = Paleta.azul700;
  static const Color infoTextoForte = Paleta.azul800;
  static const Color infoTextoIntenso = Paleta.azul900;

  /// Etiqueta de estado em cinzento sólido (acesso ao portal ligado).
  static const Color estadoAtivoFundo = Paleta.neutro650;

  /// Etiqueta de estado em cinzento apagado (acesso ao portal desligado).
  static const Color estadoInativoFundo = Paleta.neutro150;

  /// Painel de resumo analítico (carga estimada, posto gargalo).
  static const Color resumoFundo = Paleta.azulAcinzentado50;
  static const Color resumoBorda = Paleta.azulAcinzentado100;
  static const Color resumoTexto = Paleta.azulAcinzentado800;
  static const Color resumoTextoForte = Paleta.azulAcinzentado900;

  /// Estado inativo / arquivado / sem dados.
  static const Color inativo = Paleta.neutro500;
  static const Color inativoFundo = Paleta.neutro100;
  static const Color inativoBorda = Paleta.neutro300;
  static const Color inativoTexto = Paleta.neutro700;

  // ──────────────── Nomes mantidos por compatibilidade ────────────────

  static const Color laranjaAlerta = alerta;
  static const Color verdeSucesso = sucesso;
  static const Color vermelhoErro = erro;

  // ───────────────────── Acentos de categorização ─────────────────────
  // Cores sem valor semântico de estado, usadas para distinguir séries,
  // perfis ou tipos entre si (gráficos, avatares, ícones de categoria).

  static const Color acentoAzul = Paleta.azul500;
  static const Color acentoAzulEscuro = Paleta.azul800;
  static const Color acentoVerde = Paleta.verde500;
  static const Color acentoVermelho = Paleta.vermelho500;
  static const Color acentoLaranja = Paleta.laranja500;
  static const Color acentoAmbar = Paleta.ambar500;
  static const Color acentoRoxo = Paleta.roxo500;
  static const Color acentoRoxoFundo = Paleta.roxo50;
  static const Color acentoRoxoForte = Paleta.roxo600;
  static const Color acentoIndigo = Paleta.indigo500;
  static const Color acentoTurquesa = Paleta.turquesa500;
  static const Color acentoAzulAcinzentado = Paleta.azulAcinzentado500;
  static const Color acentoLaranjaEscuro = Paleta.laranjaEscuro500;
  static const Color acentoArdosia = Paleta.ardosia500;

  // ───────────────────────── Portal cliente ─────────────────────────
  // Acento próprio do portal do cliente — distinto do azul do admin/operador,
  // para o cliente reconhecer visualmente que está noutra área da aplicação.
  // Substitui o `Colors.deepPurple` que estava espalhado pelos ecrãs do portal.

  /// Cor de destaque do portal cliente (botão principal, item de menu ativo).
  static const Color clienteAcento = Paleta.violeta500;

  /// Variante mais escura, para gradientes e estados de pressão/hover.
  static const Color clienteAcentoForte = Paleta.violeta600;
  static const Color clienteAcentoEscuro = Paleta.violeta700;

  /// Variante mais clara, para ícones e traços decorativos.
  static const Color clienteAcentoClaro = Paleta.violeta400;

  /// Tintas para preencher etiquetas, badges e fundos suaves.
  static const Color clienteAcentoFundo = Paleta.violeta50;
  static const Color clienteAcentoFundoForte = Paleta.violeta100;

  // ───────────────────────────── Avatares ─────────────────────────────

  /// Paleta rotativa dos avatares. A cor de cada pessoa é escolhida a partir
  /// do nome, por isso a **ordem** desta lista faz parte da identidade visual.
  static const List<Color> paletaAvatares = [
    acentoIndigo,
    acentoTurquesa,
    acentoLaranjaEscuro,
    Paleta.purpura500,
    acentoAzul,
    acentoVerde,
    acentoVermelho,
    Paleta.castanho500,
  ];

  // ───────────────────────────── Gráficos ─────────────────────────────

  /// Topo do gradiente das barras dos gráficos.
  static const Color graficoBarraTopo = Paleta.azul400;

  /// Base do gradiente das barras dos gráficos.
  static const Color graficoBarraBase = Paleta.azul600;

  /// Estrela preenchida das avaliações de clientes.
  static const Color avaliacaoEstrela = Paleta.ambar500;

  /// Linhas de grelha e eixos.
  static const Color graficoGrelha = Paleta.neutro300;

  // ───────────────────────── Tema Material ─────────────────────────

  static ThemeData obterTema() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primariaRoxa,
        primary: primariaRoxa,
      ),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
    );
  }
}

