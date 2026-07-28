import 'dart:async';

/// Janela de coalescência dos eventos realtime nas listas.
///
/// O mesmo valor de [esperaPesquisa] (`paginacao.dart`): avançar uma fase gera
/// dois ou três eventos em dezenas de milissegundos (a ordem, o histórico e por
/// vezes uma incidência) e 300 ms junta-os todos num pedido só.
const Duration janelaRealtimeLista = Duration(milliseconds: 300);
const Duration tetoRealtimeLista = Duration(milliseconds: 1500);

/// Janela mais larga para ecrãs cujos números saem de várias queries agregadas.
///
/// O dashboard principal faz quatro queries por recarregamento e os seus
/// indicadores são de leitura contemplativa, não de reação: 1 s é a diferença
/// entre 40 e 4 pedidos numa rajada, sem que ninguém dê por isso.
const Duration janelaRealtimeAgregado = Duration(seconds: 1);
const Duration tetoRealtimeAgregado = Duration(seconds: 3);

/// Janela intermédia para ecrãs de baixo volume de eventos cujo recarregamento
/// traz mais do que uma lista — a carteira de clientes (lista + métricas) e o
/// planeamento (clientes, produtos, pedidos e últimas ordens).
const Duration janelaRealtimeCarteira = Duration(milliseconds: 500);
const Duration tetoRealtimeCarteira = Duration(seconds: 2);

/// Agrupa eventos realtime próximos num único recarregamento.
///
/// O primeiro evento de uma rajada é aplicado **imediatamente** — um debounce só
/// com aresta final atrasaria todas as atualizações, incluindo a primeira, que é
/// precisamente o atraso que se quer evitar. Os eventos seguintes que caiam
/// dentro de [janela] são fundidos num único recarregamento no fim dela, e
/// [tetoEspera] garante que uma rajada contínua não adia o ecrã indefinidamente.
///
/// Impede também recarregamentos sobrepostos: se chegar um evento enquanto um
/// pedido está no ar, fica um — e um só — recarregamento marcado para o fim.
/// Sem isto, duas respostas podiam chegar trocadas e a mais antiga escrever
/// dados velhos por cima dos novos.
class RecarregadorDebounced {
  final Future<void> Function() aoRecarregar;
  final Duration janela;
  final Duration tetoEspera;

  Timer? _timer;
  DateTime? _inicioRajada;
  bool _aCorrer = false;
  bool _pendente = false;
  bool _descartado = false;

  RecarregadorDebounced({
    required this.aoRecarregar,
    this.janela = janelaRealtimeLista,
    this.tetoEspera = tetoRealtimeLista,
  });

  /// Pede um recarregamento. Aplica-o já se não houver rajada em curso.
  void pedir() {
    if (_descartado) return;
    if (_timer == null) {
      _inicioRajada = DateTime.now();
      _armarJanela();
      _correr();
    } else {
      _pendente = true;
      _armarJanela();
    }
  }

  /// Cancela o que estiver agendado. A chamar no `dispose` do ecrã.
  void descartar() {
    _descartado = true;
    _timer?.cancel();
    _timer = null;
    _pendente = false;
  }

  void _armarJanela() {
    _timer?.cancel();
    var espera = janela;
    final inicio = _inicioRajada;
    if (inicio != null) {
      final restante = tetoEspera - DateTime.now().difference(inicio);
      if (restante < espera) espera = restante;
    }
    if (espera < Duration.zero) espera = Duration.zero;
    _timer = Timer(espera, _aoFecharJanela);
  }

  void _aoFecharJanela() {
    _timer = null;
    if (!_pendente) {
      _inicioRajada = null; // a rajada acabou
      return;
    }
    _pendente = false;
    _inicioRajada = DateTime.now();
    _armarJanela();
    _correr();
  }

  Future<void> _correr() async {
    if (_descartado) return;
    if (_aCorrer) {
      // Já há um pedido no ar: fica marcado para correr quando ele terminar.
      _pendente = true;
      return;
    }
    _aCorrer = true;
    try {
      await aoRecarregar();
    } catch (_) {
      // Os ecrãs já reportam os seus próprios erros de carregamento; aqui só
      // interessa que uma falha não deixe o recarregador preso em `_aCorrer`.
    } finally {
      _aCorrer = false;
    }
    // Se entrou um evento durante o pedido e nenhuma janela ficou aberta para o
    // apanhar, corre agora.
    if (_pendente && _timer == null && !_descartado) {
      _pendente = false;
      _inicioRajada = DateTime.now();
      _armarJanela();
      unawaited(_correr());
    }
  }
}
