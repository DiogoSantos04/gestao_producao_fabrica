import 'package:flutter/material.dart';

import '../../../core/temas_cores.dart';
import '../../../models/utilizador_model.dart';
import 'identidade_utilizador.dart';

/// Uma linha da tabela de utilizadores.
///
/// Não escreve na base de dados: as ações saem por callback e o ecrã decide o
/// que fazer com elas.
class LinhaUtilizador extends StatelessWidget {
  const LinhaUtilizador({
    super.key,
    required this.utilizador,
    required this.posto,
    required this.aoAbrirDetalhe,
    required this.aoAprovar,
    required this.aoRejeitar,
    required this.aoEditar,
    required this.aoAlterarEstado,
  });

  final UtilizadorModel utilizador;

  /// Posto atribuído ao operador, ou `null` se não tiver nenhum.
  final Map<String, dynamic>? posto;

  final VoidCallback aoAbrirDetalhe;
  final VoidCallback aoAprovar;
  final VoidCallback aoRejeitar;
  final VoidCallback aoEditar;
  final ValueChanged<EstadoConta> aoAlterarEstado;

  @override
  Widget build(BuildContext context) {
    final ut = utilizador;
    final String nome = ut.nomeUtilizador.isEmpty ? 'N/A' : ut.nomeUtilizador;
    final bool ePendente = ut.estadoConta == EstadoConta.pendente;
    final bool eAtivo = ut.estadoConta == EstadoConta.ativo;
    final bool eOperador = ut.perfil == PerfilUtilizador.operador;

    return InkWell(
      onTap: aoAbrirDetalhe,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            // Nome do Funcionário (com avatar de iniciais + posto)
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  AvatarUtilizador(nome: nome),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nome,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, color: TemasCores.textoPrimario, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (eOperador) _ChipPosto(posto: posto),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Email
            Expanded(
              flex: 4,
              child: Text(
                ut.email ?? 'N/A',
                style: const TextStyle(color: TemasCores.textoApoio, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Perfil (Badge)
            Expanded(
              flex: 2,
              child: Row(children: [EtiquetaPerfil(perfil: ut.perfil)]),
            ),
            // Estado da Conta (Badge)
            Expanded(
              flex: 2,
              child: Row(children: [EtiquetaEstadoConta(estado: ut.estadoConta)]),
            ),
            // Ações
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fluxo de pendentes: aprovar / rejeitar
                    if (ePendente) ...[
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: TemasCores.sucesso, size: 20),
                        tooltip: 'Aprovar Registo',
                        onPressed: aoAprovar,
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined, color: TemasCores.erro, size: 20),
                        tooltip: 'Rejeitar Registo',
                        onPressed: aoRejeitar,
                      ),
                    ] else
                      // Toggle rápido Ativo/Inativo (não aplicável a pendentes)
                      Tooltip(
                        message: eAtivo ? 'Desativar conta' : 'Ativar conta',
                        child: Switch(
                          value: eAtivo,
                          activeThumbColor: TemasCores.sucesso,
                          onChanged: (ligar) =>
                              aoAlterarEstado(ligar ? EstadoConta.ativo : EstadoConta.inativo),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: TemasCores.textoSecundario, size: 20),
                      tooltip: 'Editar Utilizador',
                      onPressed: aoEditar,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip pequeno com o posto de trabalho atribuído ao operador (ou "Sem posto")
class _ChipPosto extends StatelessWidget {
  const _ChipPosto({required this.posto});

  final Map<String, dynamic>? posto;

  @override
  Widget build(BuildContext context) {
    final bool temPosto = posto != null && (posto!['nome_posto']?.toString().trim().isNotEmpty ?? false);
    final String label = temPosto ? posto!['nome_posto'].toString() : 'Sem posto';
    final Color cor = temPosto ? TemasCores.acentoTurquesa : TemasCores.textoTerciario;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(temPosto ? Icons.precision_manufacturing_outlined : Icons.location_off_outlined,
              size: 12, color: cor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
