import 'package:flutter/material.dart';

import '../../../core/iniciais.dart';
import '../../../core/temas_cores.dart';
import '../../../models/utilizador_model.dart';
import '../../../widgets/etiqueta_estado.dart';

/// Avatar circular com as iniciais do nome, colorido de forma estável a partir
/// do próprio nome.
class AvatarUtilizador extends StatelessWidget {
  const AvatarUtilizador({super.key, required this.nome, this.raio = 16});

  final String nome;
  final double raio;

  @override
  Widget build(BuildContext context) {
    final iniciais = obterIniciais(
      nome,
      omissao: '?',
      letrasNomeUnico: 1,
      usarUltimoNome: true,
    );
    final cor = corAvatar(nome);

    return CircleAvatar(
      radius: raio,
      backgroundColor: cor.withValues(alpha: 0.15),
      child: Text(
        iniciais,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

/// Pílula com o cargo do utilizador.
class EtiquetaPerfil extends StatelessWidget {
  const EtiquetaPerfil({super.key, required this.perfil});

  final PerfilUtilizador perfil;

  @override
  Widget build(BuildContext context) {
    // Um perfil não reconhecido continua a apresentar-se como "Funcionário",
    // tal como antes (o `else` do encadeado original).
    final (Color fundo, Color texto) = switch (perfil) {
      PerfilUtilizador.administrador => (TemasCores.marcaEscura, TemasCores.textoInverso),
      PerfilUtilizador.tecnico => (TemasCores.avisoFundo, TemasCores.avisoTextoForte),
      PerfilUtilizador.cliente => (TemasCores.infoFundo, TemasCores.infoTextoForte),
      _ => (TemasCores.estadoInativoFundo, TemasCores.textoPrimario),
    };
    return EtiquetaEstado.pilula(rotulo: perfil.etiqueta, fundo: fundo, texto: texto);
  }
}

/// Pílula com o estado da conta.
class EtiquetaEstadoConta extends StatelessWidget {
  const EtiquetaEstadoConta({super.key, required this.estado});

  final EstadoConta estado;

  @override
  Widget build(BuildContext context) {
    final (Color fundo, Color texto) = switch (estado) {
      EstadoConta.inativo => (TemasCores.erroFundo, TemasCores.erroTexto),
      EstadoConta.pendente => (TemasCores.alertaFundo, TemasCores.alertaTexto),
      EstadoConta.ativo => (TemasCores.estadoAtivoFundo, TemasCores.textoInverso),
    };

    return EtiquetaEstado.pilula(rotulo: estado.valorBd, fundo: fundo, texto: texto);
  }
}
