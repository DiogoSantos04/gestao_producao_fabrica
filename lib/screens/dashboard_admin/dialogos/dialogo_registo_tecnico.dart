import 'package:flutter/material.dart';

import '../../../core/breakpoints.dart';
import '../../../core/mensagens.dart';
import '../../../core/temas_cores.dart';
import '../../../models/incidencia_model.dart';
import '../../../repositories/encomendas_repository.dart';

/// Registo técnico de uma incidência, em dois modos.
///
/// **Validação** — o técnico de manutenção já preencheu o relatório no terminal
/// dele. O administrador lê e prossegue; não reescreve. Antes, esta janela
/// obrigava-o a redigir um trabalho que não fez, o que produzia registos
/// inventados a partir do momento em que o técnico deixava de estar ao pé dele.
///
/// **Entrada** — não há registo do técnico. É o caso da assistência externa, em
/// que não existe conta na aplicação para quem fez a reparação, e o
/// administrador é mesmo a fonte da informação.
///
/// Devolve a mensagem de sucesso, ou `null` se o utilizador desistir.
class DialogoRegistoTecnico extends StatefulWidget {
  /// Linha da incidência ativa, tal como vem da projeção do painel.
  final Map<String, dynamic> incidencia;

  /// Técnicos internos elegíveis, com `utilizador_id`, `nome_utilizador` e `perfil`.
  final List<Map<String, dynamic>> tecnicos;

  final EncomendasRepository repositorio;

  const DialogoRegistoTecnico({
    super.key,
    required this.incidencia,
    required this.tecnicos,
    required this.repositorio,
  });

  static Future<String?> mostrar(
    BuildContext context, {
    required Map<String, dynamic> incidencia,
    required List<Map<String, dynamic>> tecnicos,
    required EncomendasRepository repositorio,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => DialogoRegistoTecnico(
        incidencia: incidencia,
        tecnicos: tecnicos,
        repositorio: repositorio,
      ),
    );
  }

  @override
  State<DialogoRegistoTecnico> createState() => _DialogoRegistoTecnicoState();
}

class _DialogoRegistoTecnicoState extends State<DialogoRegistoTecnico> {
  final _entidadeExternaController = TextEditingController();
  final _notaTecnicaController = TextEditingController();

  late final IncidenciaModel _incidencia;

  String _tipoManutencao = 'INTERNA'; // 'INTERNA' ou 'EXTERNA'
  String? _tecnicoId;
  bool _aGravar = false;

  bool get _eInterna => _tipoManutencao == 'INTERNA';

  /// O técnico já deixou registo próprio: nada aqui é para reescrever.
  bool get _modoValidacao => _incidencia.temRegistoDoTecnico;

  @override
  void initState() {
    super.initState();
    _incidencia = IncidenciaModel.fromJson(widget.incidencia);

    // Sem registo interno, o caso provável é a assistência externa — se houvesse
    // técnico da casa disponível, o registo teria vindo do terminal dele.
    if (!_modoValidacao && _incidencia.tecnicoId == null) {
      _tipoManutencao = 'EXTERNA';
    }
  }

  @override
  void dispose() {
    _entidadeExternaController.dispose();
    _notaTecnicaController.dispose();
    super.dispose();
  }

  Future<void> _concluir() async {
    if (_eInterna && _tecnicoId == null) {
      context.mostrarMensagem('Selecione o técnico interno responsável.', eErro: true);
      return;
    }
    if (!_eInterna && _entidadeExternaController.text.trim().isEmpty) {
      context.mostrarMensagem('Indique a empresa de assistência externa.', eErro: true);
      return;
    }
    if (_notaTecnicaController.text.trim().isEmpty) {
      context.mostrarMensagem(
        'Descreva os trabalhos efetuados — é este o registo da intervenção.',
        eErro: true,
      );
      return;
    }

    setState(() => _aGravar = true);
    try {
      await widget.repositorio.registarIntervencaoTecnica(
        incidenciaId: _incidencia.id,
        tipoManutencao: _tipoManutencao,
        tecnicoId: _eInterna ? _tecnicoId : null,
        entidadeExterna:
            _eInterna ? null : _entidadeExternaController.text.trim(),
        notaTecnica: _notaTecnicaController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        '🛠️ Registo técnico concluído! A ordem aguarda agora Line Clearance.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _aGravar = false);
      context.mostrarMensagem(
        'Erro ao gravar registo técnico: ${mensagemDeErro(e)}',
        eErro: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _modoValidacao
                ? Icons.fact_check_outlined
                : Icons.build_circle_rounded,
            color: TemasCores.avisoTextoForte,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _modoValidacao
                  ? 'Registo Técnico da Manutenção'
                  : 'Registo Técnico de Intervenção',
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: larguraDialogo(context, 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cabecalhoIncidencia(),
              if (_modoValidacao) ..._blocoValidacao() else ..._blocoEntrada(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _aGravar ? null : () => Navigator.pop(context),
          child: Text(_modoValidacao ? 'Fechar' : 'Cancelar'),
        ),
        if (!_modoValidacao)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: TemasCores.avisoTexto,
              foregroundColor: TemasCores.textoInverso,
            ),
            icon: _aGravar
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: TemasCores.textoInverso,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Concluir Intervenção Técnica'),
            onPressed: _aGravar ? null : _concluir,
          ),
      ],
    );
  }

  Widget _cabecalhoIncidencia() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: TemasCores.avisoFundo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: TemasCores.avisoBorda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Incidente: ${_incidencia.rotulo ?? 'Manutenção Requerida'}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: TemasCores.avisoTextoForte,
            ),
          ),
          if ((_incidencia.descricaoOperador ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Relato do operador: ${_incidencia.descricaoOperador!.trim()}',
              style: const TextStyle(
                fontSize: 11,
                color: TemasCores.avisoTexto,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- MODO VALIDAÇÃO: o técnico já preencheu ---

  List<Widget> _blocoValidacao() {
    final duracao = _incidencia.duracaoIntervencao;
    final espera = _incidencia.tempoEspera;

    return [
      Row(
        children: [
          const Icon(Icons.engineering_rounded,
              size: 16, color: TemasCores.sucessoForte),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Preenchido por ${_incidencia.responsavelIntervencao ?? 'técnico de manutenção'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: TemasCores.sucessoTextoForte,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if ((_incidencia.diagnostico ?? '').trim().isNotEmpty)
        _campoLido('Diagnóstico da avaria', _incidencia.diagnostico!),
      if ((_incidencia.notaTecnica ?? '').trim().isNotEmpty)
        _campoLido('Ações realizadas', _incidencia.notaTecnica!),
      if ((_incidencia.pecasSubstituidas ?? '').trim().isNotEmpty)
        _campoLido('Peças substituídas', _incidencia.pecasSubstituidas!),
      if (duracao != null || espera != null)
        _campoLido(
          'Tempos',
          [
            if (espera != null) 'Espera: ${_duracao(espera)}',
            if (duracao != null) 'Reparação: ${_duracao(duracao)}',
          ].join('   ·   '),
        ),
      const SizedBox(height: 6),
      const Text(
        'Estes dados foram registados por quem executou a intervenção e não são '
        'editáveis aqui. A ordem aguarda Line Clearance.',
        style: TextStyle(fontSize: 11, color: TemasCores.textoTerciario),
      ),
    ];
  }

  Widget _campoLido(String rotulo, String valor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: TemasCores.superficieTenue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TemasCores.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: TemasCores.textoTerciario,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valor.trim(),
            style: const TextStyle(
              fontSize: 13,
              color: TemasCores.textoPrimario,
            ),
          ),
        ],
      ),
    );
  }

  static String _duracao(Duration d) {
    final horas = d.inHours;
    final minutos = d.inMinutes.remainder(60);
    if (horas > 0) return '${horas}h ${minutos}m';
    return '${d.inMinutes}m';
  }

  // --- MODO ENTRADA: assistência externa ou registo em falta ---

  List<Widget> _blocoEntrada() {
    return [
      const Text(
        'Tipo de Intervenção Técnica:',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
      const SizedBox(height: 8),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'INTERNA',
            label: Text('Manutenção Interna'),
            icon: Icon(Icons.engineering_rounded, size: 16),
          ),
          ButtonSegment(
            value: 'EXTERNA',
            label: Text('Assistência Externa'),
            icon: Icon(Icons.fire_truck_rounded, size: 16),
          ),
        ],
        selected: {_tipoManutencao},
        onSelectionChanged: _aGravar
            ? null
            : (nova) => setState(() => _tipoManutencao = nova.first),
      ),
      const SizedBox(height: 16),
      if (_eInterna) ...[
        if (widget.tecnicos.isEmpty)
          const Text(
            'Não há nenhum utilizador com perfil de Técnico de Manutenção. '
            'Atribua o perfil na Gestão de Utilizadores, ou registe a '
            'intervenção como assistência externa.',
            style: TextStyle(fontSize: 12, color: TemasCores.erroForte),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _tecnicoId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Técnico Responsável *',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.tecnicos.map((u) {
              final id = u['utilizador_id'].toString();
              final nome = u['nome_utilizador'] ?? 'Sem nome';
              return DropdownMenuItem<String>(
                value: id,
                child: Text(nome.toString(),
                    style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged:
                _aGravar ? null : (val) => setState(() => _tecnicoId = val),
          ),
      ] else ...[
        TextField(
          controller: _entidadeExternaController,
          enabled: !_aGravar,
          decoration: const InputDecoration(
            labelText: 'Empresa / Entidade Externa *',
            hintText: 'Ex: Siemens, Kuka Robotics, EletroCaldas',
            border: OutlineInputBorder(),
          ),
        ),
      ],
      const SizedBox(height: 14),
      TextField(
        controller: _notaTecnicaController,
        enabled: !_aGravar,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Relatório Técnico / Ações Corretivas *',
          hintText:
              'Descreva os trabalhos efetuados, peças substituídas ou calibração efetuada...',
          border: OutlineInputBorder(),
        ),
      ),
    ];
  }
}
