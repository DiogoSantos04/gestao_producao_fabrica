import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/temas_cores.dart';
import '../../models/estado_ordem.dart';
import '../../repositories/base_repository.dart';
import '../../repositories/portal_cliente_repository.dart';
import '../../widgets/dialogo_suporte.dart';
import '../../widgets/etiqueta_estado.dart';

/// Consulta pública do estado de fabrico de uma encomenda.
///
/// O ecrã é acessível sem sessão iniciada (a partir do ecrã de login), pelo que
/// os dados vêm da função `rastrear_encomenda`, que devolve apenas o roteiro e o
/// estado. A consulta direta à tabela `encomendas` que existia aqui devolvia
/// também `clientes(nome_cliente)`: com códigos de formato enumerável, bastava
/// tentar códigos para descobrir que cliente encomendou o quê — ver bug (C).
class RastreioClienteScreen extends StatefulWidget {
  const RastreioClienteScreen({super.key, this.codigoInicial});

  /// Código a consultar mal o ecrã abre, sem o cliente ter de o copiar.
  ///
  /// É por aqui que entra a ligação enviada no email de arranque da produção
  /// (`?codigo=` no endereço do portal): quem a segue vê o estado da encomenda
  /// diretamente, que é o ponto de o rastreio ser público.
  final String? codigoInicial;

  @override
  State<RastreioClienteScreen> createState() => RastreioClienteScreenState();
}

class RastreioClienteScreenState extends State<RastreioClienteScreen> {
  final PortalClienteRepository _repositorio = PortalClienteRepository();
  final _codigoController = TextEditingController();

  bool _isLoading = false;
  RastreioEncomenda? _encomenda;
  String? _erro;

  /// Confirmação de receção em curso — desativa o botão para evitar duplo envio.
  bool _aConfirmarRececao = false;

  /// Código atualmente apresentado, usado para refazer a consulta quando a
  /// produção avança.
  String? _codigoEmCurso;

  RealtimeChannel? _canal;
  Timer? _agendamentoRecarga;

  @override
  void initState() {
    super.initState();

    final codigo = widget.codigoInicial?.trim().toUpperCase();
    if (codigo == null || codigo.isEmpty) return;

    _codigoController.text = codigo;
    // Depois do primeiro frame: a consulta acaba em `setState`, e o ecrã ainda
    // não está montado enquanto `initState` corre.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _buscarRastreio();
    });
  }

  @override
  void dispose() {
    _agendamentoRecarga?.cancel();
    final canal = _canal;
    if (canal != null) Supabase.instance.client.removeChannel(canal);
    _codigoController.dispose();
    super.dispose();
  }

  /// Consulta um código vindo de fora do ecrã.
  ///
  /// É o que liga a notificação ao rastreio: o separador já está montado dentro
  /// do `IndexedStack` do portal, por isso não basta reconstruí-lo com outro
  /// [RastreioClienteScreen.codigoInicial] — é preciso pedir-lhe a consulta.
  void consultarCodigo(String codigo) {
    final valor = codigo.trim().toUpperCase();
    if (valor.isEmpty) return;

    _codigoController.text = valor;
    _buscarRastreio();
  }

  Future<void> _buscarRastreio({bool silencioso = false}) async {
    final codigo = silencioso
        ? (_codigoEmCurso ?? '')
        : _codigoController.text.trim().toUpperCase();
    if (codigo.isEmpty) return;

    // Uma atualização vinda do realtime não deve apagar o cartão que o cliente
    // está a ver nem piscar o indicador de progresso.
    if (!silencioso) {
      setState(() {
        _isLoading = true;
        _encomenda = null;
        _erro = null;
      });
    }

    try {
      final resultado = await _repositorio.rastrear(codigo);

      // Cada `setState` a seguir a um `await` precisa da guarda: sair do
      // separador durante uma pesquisa lenta rebentava com
      // `setState() called after dispose()` — ver bug (E).
      if (!mounted) return;
      setState(() {
        _encomenda = resultado;
        _erro = resultado == null ? 'Nenhuma encomenda encontrada com o código informado.' : null;
        _isLoading = false;
        _codigoEmCurso = resultado == null ? null : codigo;
      });

      if (resultado != null) _ligarRealtime();
    } on RepositoryException catch (e) {
      if (!mounted) return;
      // Uma falha na atualização automática não deve substituir por um erro o
      // cartão que o cliente já tem à frente.
      if (silencioso) {
        debugPrint('Falha ao atualizar o rastreio: ${e.mensagem}');
        return;
      }
      setState(() {
        _erro = e.mensagem;
        _isLoading = false;
      });
    }
  }

  /// Acompanha o avanço da produção sem o cliente ter de repetir a pesquisa.
  ///
  /// O ecrã prometia "tempo real" desde o início, mas só atualizava a pedido.
  void _ligarRealtime() {
    if (_canal != null) return;

    _canal = _repositorio.escutarAtividadeDoCliente(
      'portal-cliente-rastreio-${DateTime.now().microsecondsSinceEpoch}',
      _agendarRecarga,
    );
  }

  void _agendarRecarga() {
    _agendamentoRecarga?.cancel();
    _agendamentoRecarga = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _buscarRastreio(silencioso: true);
    });
  }

  /// Abre o canal de suporte com o código de rastreio já no assunto — fecha o
  /// "Contactar Suporte" que o protótipo (Figura 20, "Estado da Encomenda")
  /// previa mas nunca chegou a implementar.
  ///
  /// O diálogo é partilhado com o resto do portal ([mostrarDialogoSuporte]),
  /// para o contacto ser obtido e apresentado da mesma forma em todo o lado.
  bool get _temSessao => Supabase.instance.client.auth.currentUser != null;

  void _contactarSuporte(RastreioEncomenda enc) {
    mostrarDialogoSuporte(
      context,
      aoObterEmail: _repositorio.obterEmailSuporte,
      codigoRastreio: enc.codigoRastreio.isEmpty ? null : enc.codigoRastreio,
    );
  }

  String _formatarData(DateTime? data) {
    if (data == null) return 'A definir';
    final d = data.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatarDataHora(DateTime data) {
    final d = data.toLocal();
    final hora = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${_formatarData(d)} às $hora';
  }

  /// Pede confirmação e regista a receção física da encomenda.
  ///
  /// A confirmação é pedida porque a operação não tem volta do lado do cliente:
  /// a função no servidor recusa uma segunda confirmação, para a data registada
  /// não poder ser reescrita mais tarde.
  Future<void> _confirmarRececao(RastreioEncomenda enc) async {
    final id = enc.id;
    if (id == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar receção'),
        content: Text(
          'Confirma que recebeu a encomenda ${enc.codigoRastreio}?\n\n'
          'A data e hora ficam registadas e não podem ser alteradas depois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;
    if (!mounted) return;
    setState(() => _aConfirmarRececao = true);

    try {
      await _repositorio.confirmarRececao(id);
      if (!mounted) return;
      // Relê em vez de assumir: a data que passa a ser mostrada é a do relógio
      // do servidor, e não a do dispositivo.
      await _buscarRastreio(silencioso: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receção confirmada. Obrigado!'),
          backgroundColor: TemasCores.sucesso,
        ),
      );
    } on RepositoryException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.mensagem), backgroundColor: TemasCores.erro),
      );
    } finally {
      if (mounted) setState(() => _aConfirmarRececao = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // O ecrã tem dois donos: é empilhado a partir do login (rastreio público) e
    // é também o primeiro separador do portal. Só no primeiro caso há para onde
    // recuar, por isso o botão segue o que a navegação permite em vez de um
    // parâmetro que os dois sítios teriam de manter certo.
    final bool podeVoltar = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: TemasCores.fundoEcraFrio,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Abaixo desta largura o campo e o botão deixam de caber lado a
            // lado sem cortar o texto do código.
            final bool estreito = constraints.maxWidth < 560;

            return Column(
              children: [
                if (podeVoltar)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: TextButton.styleFrom(
                          foregroundColor: TemasCores.textoApoioFrio,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('Voltar'),
                      ),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      estreito ? 20 : 32,
                      podeVoltar ? 8 : 32,
                      estreito ? 20 : 32,
                      32,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 650),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _construirCabecalho(estreito),
                            SizedBox(height: estreito ? 20 : 28),
                            _construirPesquisa(estreito),
                            const SizedBox(height: 20),
                            if (_isLoading)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Center(
                                  child: CircularProgressIndicator(color: TemasCores.clienteAcento),
                                ),
                              ),
                            if (_erro != null) _construirErro(_erro!),
                            if (_encomenda != null) _construirResultado(_encomenda!),
                            // Sem pesquisa feita o ecrã ficava vazio por baixo da
                            // caixa. A ajuda ocupa esse espaço com a única coisa
                            // que falta ao cliente: onde encontrar o código.
                            if (!_isLoading && _erro == null && _encomenda == null)
                              _construirAjudaInicial(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _construirCabecalho(bool estreito) {
    final double lado = estreito ? 60 : 72;

    return Column(
      children: [
        Container(
          width: lado,
          height: lado,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [TemasCores.clienteAcentoClaro, TemasCores.clienteAcentoForte],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: TemasCores.sombraTenue, blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Icon(
            Icons.local_shipping_outlined,
            size: estreito ? 28 : 34,
            color: TemasCores.textoInverso,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Rastreio de Encomendas',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: estreito ? 22 : 26,
            fontWeight: FontWeight.bold,
            color: TemasCores.textoPrimarioFrio,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Insira o código de rastreio para acompanhar o estado do seu pedido em tempo real.',
          textAlign: TextAlign.center,
          style: TextStyle(color: TemasCores.textoSecundarioFrio, fontSize: 14),
        ),
      ],
    );
  }

  /// Caixa de pesquisa. Em ecrãs estreitos o botão passa para baixo do campo,
  /// com o rótulo por extenso — uma seta sozinha num telemóvel não diz o que faz.
  Widget _construirPesquisa(bool estreito) {
    final bool temTexto = _codigoController.text.trim().isNotEmpty;

    final Widget campo = TextField(
      controller: _codigoController,
      autofocus: false,
      decoration: InputDecoration(
        hintText: 'Código de rastreio (ex.: TRC-XXXXXX)',
        border: InputBorder.none,
        prefixIcon: const Icon(Icons.qr_code_2_rounded, color: TemasCores.textoTerciarioFrio),
        suffixIcon: temTexto
            ? IconButton(
                tooltip: 'Limpar',
                icon: const Icon(Icons.close_rounded, size: 18, color: TemasCores.textoTerciarioFrio),
                onPressed: () {
                  _codigoController.clear();
                  setState(() {
                    _encomenda = null;
                    _erro = null;
                    _codigoEmCurso = null;
                  });
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _buscarRastreio(),
    );

    final Widget botao = ElevatedButton.icon(
      onPressed: _isLoading ? null : _buscarRastreio,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: estreito ? 20 : 24),
        minimumSize: estreito ? const Size.fromHeight(48) : null,
        backgroundColor: TemasCores.clienteAcento,
        foregroundColor: TemasCores.textoInverso,
        disabledBackgroundColor: TemasCores.clienteAcentoClaro,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: TemasCores.textoInverso),
            )
          : const Icon(Icons.search_rounded, size: 20),
      label: Text(estreito ? 'Rastrear encomenda' : 'Rastrear'),
    );

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: TemasCores.superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TemasCores.borda),
        boxShadow: const [
          BoxShadow(color: TemasCores.sombraTenue, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: estreito
          ? Column(
              children: [
                campo,
                const SizedBox(height: 8),
                botao,
              ],
            )
          : Row(
              children: [
                Expanded(child: campo),
                const SizedBox(width: 8),
                botao,
              ],
            ),
    );
  }

  Widget _construirErro(String mensagem) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemasCores.erroFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.erroBorda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 20, color: TemasCores.erroTextoForte),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensagem,
              style: const TextStyle(
                color: TemasCores.erroTextoForte,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ajuda mostrada enquanto não há pesquisa feita.
  Widget _construirAjudaInicial() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TemasCores.clienteAcentoFundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TemasCores.clienteAcentoFundoForte),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: TemasCores.clienteAcentoForte),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'O código de rastreio começa por TRC- e consta da confirmação da '
              'sua encomenda. O estado mostrado atualiza-se sozinho à medida que '
              'a produção avança.',
              style: TextStyle(fontSize: 13, color: TemasCores.clienteAcentoEscuro, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirResultado(RastreioEncomenda enc) {
    // O estado sai da regra única de `EstadoOrdem`, e não do nome da fase: uma
    // encomenda cancelada ou suspensa aparecia antes como se estivesse a
    // avançar normalmente — ver bug (B).
    final estado = EstadoOrdem.derivar(
      cancelada: enc.cancelada,
      emSuspenso: enc.emSuspenso,
      temFaseAtual: enc.faseAtualId != null,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: TemasCores.borda),
      ),
      color: TemasCores.superficie,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  enc.codigoRastreio.isEmpty ? 'Sem código' : enc.codigoRastreio,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: TemasCores.textoApoioIntensoFrio),
                ),
                EtiquetaEstado.destacada(
                  rotulo: enc.nomeProduto ?? 'Artigo',
                  fundo: TemasCores.clienteAcentoFundo,
                  texto: TemasCores.clienteAcentoForte,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _construirBadgeEstado(estado, enc),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.event, size: 16, color: TemasCores.textoSecundarioFrio),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Data Prevista de Entrega: ${_formatarData(enc.dataEntrega)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: TemasCores.textoSecundarioFrio, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            const Divider(height: 32, color: TemasCores.borda),
            const Text(
              'Etapas de Fabrico',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: TemasCores.textoPrimarioFrio),
            ),
            const SizedBox(height: 20),
            if (enc.faseAtualDesconhecida)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TemasCores.alertaFundo,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: TemasCores.alertaBorda),
                  ),
                  child: const Text(
                    'A etapa em curso não consta do roteiro atual deste artigo. '
                    'O progresso detalhado não pode ser apresentado — contacte-nos para mais informação.',
                    style: TextStyle(fontSize: 12, color: TemasCores.alertaTextoForte),
                  ),
                ),
              ),
            if (enc.fases.isEmpty)
              const Text(
                'Ainda não há um roteiro de fabrico associado a este artigo.',
                style: TextStyle(fontSize: 13, color: TemasCores.textoSecundarioFrio),
              )
            else
              ...List.generate(enc.fases.length, (index) => _construirEtapa(enc, estado, index)),
            // A entrega só entra na linha temporal depois de a produção acabar:
            // é o passo que fecha a rastreabilidade do lado do destinatário.
            if (estado == EstadoOrdem.concluida) _construirEtapaRececao(enc),
            // Sem sessão iniciada (o rastreio é público) a RPC do contacto não
            // é executável, e mostrar um botão que só devolve erro é pior do
            // que não o mostrar.
            if (_temSessao) ...[
              const Divider(height: 32, color: TemasCores.borda),
              OutlinedButton.icon(
                onPressed: () => _contactarSuporte(enc),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: TemasCores.clienteAcento,
                  side: const BorderSide(color: TemasCores.clienteAcentoClaro),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.support_agent_outlined, size: 18),
                label: const Text('Contactar Suporte'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Badge de estado tal como o cliente o vê.
  ///
  /// "RECEBIDA" é um rótulo de apresentação, não um [EstadoOrdem]: no servidor e
  /// nos indicadores estas ordens continuam concluídas.
  Widget _construirBadgeEstado(EstadoOrdem estado, RastreioEncomenda enc) {
    final bool recebida = estado == EstadoOrdem.concluida && enc.rececaoConfirmada;
    final cores = coresEstadoOrdem(estado);

    return EtiquetaEstado.destacada(
      rotulo: recebida
          ? 'RECEBIDA'
          : estado == EstadoOrdem.emHold
              ? 'PRODUÇÃO SUSPENSA'
              : estado.etiqueta,
      fundo: cores.fundo,
      texto: cores.texto,
    );
  }

  /// Etapa final da linha temporal: a entrega ao destinatário.
  ///
  /// Só aparece depois de a produção terminar. Enquanto a encomenda estiver na
  /// linha, anunciar uma etapa de entrega que ainda não se pode cumprir seria
  /// prometer ao cliente um passo que não controla.
  Widget _construirEtapaRececao(RastreioEncomenda enc) {
    final data = enc.dataConfirmacaoRececao;
    final bool confirmada = data != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          confirmada ? Icons.inventory_2 : Icons.inventory_2_outlined,
          color: confirmada ? TemasCores.sucesso : TemasCores.textoTerciarioFrio,
          size: 22,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Receção pelo cliente',
                style: TextStyle(
                  fontWeight: confirmada ? FontWeight.bold : FontWeight.normal,
                  color: confirmada
                      ? TemasCores.sucessoTextoForte
                      : TemasCores.textoSecundarioFrio,
                  fontSize: 14,
                ),
              ),
              Text(
                confirmada
                    ? 'Confirmada em ${_formatarDataHora(data)}'
                    : 'Por confirmar',
                style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciarioFrio),
              ),
              if (!confirmada) ...[
                const SizedBox(height: 10),
                if (_temSessao)
                  FilledButton.icon(
                    onPressed: _aConfirmarRececao ? null : () => _confirmarRececao(enc),
                    style: FilledButton.styleFrom(
                      backgroundColor: TemasCores.sucesso,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _aConfirmarRececao
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Confirmar Receção'),
                  )
                else
                  // O rastreio é público, mas confirmar é um ato identificado.
                  const Text(
                    'Inicie sessão no portal para confirmar a receção.',
                    style: TextStyle(fontSize: 12, color: TemasCores.textoSecundarioFrio, fontStyle: FontStyle.italic),
                  ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirEtapa(RastreioEncomenda enc, EstadoOrdem estado, int index) {
    final fase = enc.fases[index];
    final indiceAtual = enc.indiceFaseAtual;
    final bool emHold = estado == EstadoOrdem.emHold;

    // Sem fase atual conhecida há dois casos distintos: a ordem percorreu o
    // roteiro todo (concluída) ou a fase gravada já não existe. Só o primeiro
    // justifica marcar as etapas como concluídas.
    final bool isConcluida = indiceAtual != null
        ? index < indiceAtual
        : (estado == EstadoOrdem.concluida && !enc.faseAtualDesconhecida);
    final bool isFaseAtual = indiceAtual != null && index == indiceAtual;

    final Color corIcone = isConcluida
        ? TemasCores.sucesso
        : isFaseAtual
            ? (emHold ? TemasCores.erro : TemasCores.clienteAcento)
            : TemasCores.textoTerciarioFrio;

    final String legenda = isConcluida
        ? 'Concluída'
        : isFaseAtual
            ? (emHold ? 'Suspensa' : 'Em Processamento')
            : 'Pendente';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              isConcluida
                  ? Icons.check_circle
                  : isFaseAtual
                      ? (emHold ? Icons.pause_circle_filled : Icons.play_circle_filled)
                      : Icons.radio_button_unchecked,
              color: corIcone,
              size: 22,
            ),
            // A última fase passa a ter conector quando a etapa de receção a
            // segue, para a linha não ficar interrompida antes do fim.
            if (index < enc.fases.length - 1 || estado == EstadoOrdem.concluida)
              Container(
                width: 2,
                height: 36,
                color: isConcluida ? TemasCores.sucesso : TemasCores.borda,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fase.nome,
                style: TextStyle(
                  fontWeight: (isFaseAtual || isConcluida) ? FontWeight.bold : FontWeight.normal,
                  color: isFaseAtual
                      ? (emHold ? TemasCores.erroTextoForte : TemasCores.clienteAcentoForte)
                      : isConcluida
                          ? TemasCores.sucessoTextoForte
                          : TemasCores.textoSecundarioFrio,
                  fontSize: 14,
                ),
              ),
              Text(
                legenda,
                style: const TextStyle(fontSize: 12, color: TemasCores.textoTerciarioFrio),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
