import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/utilizador_model.dart';
import '../../../repositories/utilizadores_repository.dart';
import 'identidade_utilizador.dart';

/// Painel lateral com a visão 360º de um colaborador.
///
/// As métricas são lidas aqui, não no ecrã: são exclusivas deste painel e o
/// `FutureBuilder` já trata do estado de espera e de erro.
class PainelDetalheUtilizador extends StatelessWidget {
  const PainelDetalheUtilizador({
    super.key,
    required this.utilizador,
    required this.posto,
    required this.repositorio,
    required this.aoEditar,
  });

  final UtilizadorModel utilizador;

  /// Posto atribuído ao operador, ou `null` se não tiver nenhum.
  final Map<String, dynamic>? posto;

  final UtilizadoresRepository repositorio;

  /// Chamado depois de o painel se fechar.
  final VoidCallback aoEditar;

  /// Abre o painel a deslizar da direita.
  static Future<void> mostrar(
    BuildContext context, {
    required UtilizadorModel utilizador,
    required Map<String, dynamic>? posto,
    required UtilizadoresRepository repositorio,
    required VoidCallback aoEditar,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar',
      barrierColor: TemasCores.veuModal,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, anim1, anim2) => PainelDetalheUtilizador(
        utilizador: utilizador,
        posto: posto,
        repositorio: repositorio,
        aoEditar: aoEditar,
      ),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final offset = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut));
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ut = utilizador;
    final String nome = ut.nomeUtilizador.isEmpty ? 'N/A' : ut.nomeUtilizador;

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: TemasCores.superficie,
        child: SizedBox(
          width: 420,
          height: double.infinity,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabeçalho do painel
                  Row(
                    children: [
                      AvatarUtilizador(nome: nome),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(ut.email ?? 'N/A',
                                style: const TextStyle(fontSize: 13, color: TemasCores.textoApoio)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      EtiquetaPerfil(perfil: ut.perfil),
                      const SizedBox(width: 8),
                      EtiquetaEstadoConta(estado: ut.estadoConta),
                    ],
                  ),
                  const Divider(height: 32),

                  // Posto atribuído
                  _LinhaDetalhe(
                    icone: Icons.precision_manufacturing_outlined,
                    titulo: 'Posto atribuído',
                    valor: posto != null && (posto!['nome_posto']?.toString().isNotEmpty ?? false)
                        ? '${posto!['nome_posto']}  (${posto!['estado'] ?? 'N/D'})'
                        : 'Nenhum posto atribuído',
                    cor: TemasCores.acentoTurquesa,
                  ),

                  // Métricas carregadas de forma assíncrona
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: repositorio.obterMetricas(ut.utilizadorId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Text('Erro ao carregar métricas: ${snapshot.error}',
                                style: const TextStyle(color: TemasCores.erro)),
                          );
                        }
                        final m = snapshot.data ?? {};
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LinhaDetalhe(
                              icone: Icons.check_circle_outline,
                              titulo: 'Fases de produção concluídas',
                              valor: '${m['fasesConcluidas'] ?? 0}',
                              cor: TemasCores.sucesso,
                            ),
                            _LinhaDetalhe(
                              icone: Icons.schedule,
                              titulo: 'Última atividade',
                              valor: _formatarData(m['ultimaAtividade']),
                              cor: TemasCores.acentoIndigo,
                            ),
                            _LinhaDetalhe(
                              icone: Icons.build_outlined,
                              titulo: 'Intervenções como técnico',
                              valor: '${m['incidencias'] ?? 0}',
                              cor: TemasCores.acentoLaranjaEscuro,
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Ação de edição a partir do painel
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        aoEditar();
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Editar Utilizador'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatarData(dynamic valor) {
  if (valor == null) return 'Sem registo';
  try {
    final dt = DateTime.parse(valor.toString()).toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(dt.day)}/${dois(dt.month)}/${dt.year} ${dois(dt.hour)}:${dois(dt.minute)}';
  } catch (_) {
    return valor.toString();
  }
}

class _LinhaDetalhe extends StatelessWidget {
  const _LinhaDetalhe({
    required this.icone,
    required this.titulo,
    required this.valor,
    required this.cor,
  });

  final IconData icone;
  final String titulo;
  final String valor;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: cor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, color: TemasCores.textoApoio)),
                const SizedBox(height: 2),
                Text(valor,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: TemasCores.textoPrimario)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
