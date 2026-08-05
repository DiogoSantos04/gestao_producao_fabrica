# Revisão do módulo `portal_cliente`

Análise estática de `lib/screens/portal_cliente/` (4 ficheiros, 1659 linhas), feita
em 2026-08-01, antes de qualquer nova funcionalidade. Nada foi alterado ainda:
este documento é o inventário do que está mal e a ordem por que deve ser
resolvido.

| Ficheiro | Linhas |
|---|---|
| `cliente_shell_screen.dart` | 594 |
| `historico_cliente_screen.dart` | 447 |
| `rastreio_cliente_screen.dart` | 316 |
| `solicitar_encomenda_screen.dart` | 302 |

## Estado das correções

| Secção | Estado |
|---|---|
| 1. Bugs críticos (A)–(F) | ✅ resolvidos (2026-08-01) |
| 2. Bugs de segundo nível (1–11) | ✅ resolvidos (2026-08-02) |
| 3. Dívida arquitetural | 🟡 parcial (faltam os pontos 3 a 6, 8 e 9) |
| 4. Testes | 🟡 11 testes novos; falta cobrir o histórico e o pedido |
| RLS | ⬜ adiado por decisão: só é ligado no fim da vistoria, para que um erro novo seja atribuível |

## Resumo

O portal do cliente é o único módulo que **não passou por nenhum dos refactors**
feitos no `dashboard_admin` e no `terminal_operador`. Consequência: fala
diretamente com o Supabase a partir dos widgets, não usa nenhum dos modelos de
domínio (`EstadoOrdem`, `EncomendaModel`, `ClienteModel`, `PedidoModel`), nenhum
dos repositórios, e reimplementa localmente utilitários que já existem em
`lib/core/` (`obterIniciais`, `Formatos`, `MensagensContexto`, `TemasCores`,
`PaginaResultado`, `EcraRecarregavel`).

Contagem: **6 problemas críticos**, **11 de segundo nível**, **9 pontos de dívida
arquitetural**, **0 testes**.

O problema mais grave não é de código: a identidade do cliente é resolvida por
**comparação de nomes em texto** entre `utilizadores.nome_utilizador` e
`clientes.nome_cliente`. É simultaneamente um bug de dados e uma falha de
isolamento entre clientes.

---

## 1. Bugs críticos

### (A) Identidade do cliente resolvida por nome — risco de fuga de dados — ✅ resolvido

`historico_cliente_screen.dart:37-61` e `solicitar_encomenda_screen.dart:59-77`
fazem o mesmo:

```dart
final utilizadorData = await _supabase.from('utilizadores')
    .select('nome_utilizador').eq('utilizador_id', user.id).maybeSingle();
final clienteData = await _supabase.from('clientes')
    .select('id').eq('nome_cliente', _nomeCliente).maybeSingle();
```

Consequências reais:

1. **Dois clientes com o mesmo nome** ("Silva & Filhos" registado duas vezes,
   ou um nome de empresa repetido) — `maybeSingle()` rebenta com erro PostgREST
   ou, pior, se um deles for apagado, o utilizador passa a ver o histórico do
   outro. Um cliente vê encomendas de outro cliente.
2. **Renomear um cliente no painel admin desliga o portal**: o histórico fica
   vazio e o botão de submeter pedido deixa de funcionar com a mensagem
   "O seu utilizador não está associado a um registo na tabela de Clientes".
3. Diferenças de espaços, maiúsculas ou acentuação partem a correspondência
   silenciosamente (o `.eq` é exato e sensível a maiúsculas).

**Correção:** adicionar `clientes.utilizador_id uuid REFERENCES auth.users(id)`
(ou `clientes_id` em `utilizadores`), migrar os dados existentes por nome uma
única vez, e passar a resolver por chave estrangeira num só sítio
(`ClientesRepository.obterDoUtilizadorAutenticado()`).

#### Resolução (2026-08-01)

Correção da análise: a coluna `clientes.utilizador_id` **já existia** — foi
criada quando se corrigiu o bug (f) do `BUGS_RESOLVIDOS.md`, aponta para
`utilizadores(utilizador_id)`, e o `dashboard_admin` já a usava
(`clientes_repository.dart:18`, `pedidos_clientes_admin_screen.dart:187`). O que
existia mesmo era o portal do cliente ser o **único módulo que a ignorava**,
continuando a comparar nomes. A gravidade mantém-se; a correção ficou mais
barata.

- Migração `ligar_clientes_ao_utilizador_autenticado`: preencheu os
  `utilizador_id` em falta pela correspondência de nome — feita **uma vez**, no
  servidor, tolerante a espaços e maiúsculas (o `.eq` do portal era exato) — e
  criou o índice único parcial `clientes_utilizador_id_key`, que impede que uma
  conta passe a representar dois clientes.
- Estado dos dados no momento da migração: 4 clientes, 1 conta com perfil de
  cliente, 1 correspondência, 0 nomes duplicados. Nenhuma ambiguidade a
  resolver à mão.
- `PortalClienteRepository.obterClienteAutenticado()`
  (`lib/repositories/portal_cliente_repository.dart`) é agora o **único** sítio
  onde a identidade é resolvida, e resolve-a por
  `.eq('utilizador_id', utilizadorAtualId)`.
- Os dois ecrãs que faziam a dupla consulta por nome
  (`historico_cliente_screen.dart`, `solicitar_encomenda_screen.dart`) passaram
  a chamá-lo. Uma conta sem cliente associado deixa de dar uma lista vazia
  silenciosa e passa a dizê-lo: *"A sua conta ainda não está associada a um
  registo de cliente."*
- Renomear um cliente no painel de administração deixa de ter qualquer efeito
  sobre o portal.

### (B) O portal ignora `cancelada` e `em_suspenso` — mostra estado falso — ✅ resolvido

`historico_cliente_screen.dart:287-299` deriva o estado assim:

```dart
final bool eFinalizado = !temFaseAtual ||
    (faseNome != null && (faseNome.toLowerCase().contains('concluí') || ...));
```

Nem o `select` (linhas 65-74) nem o `rastreio_cliente_screen.dart:40-48` pedem
as colunas `cancelada` e `em_suspenso`. Resultado:

- Encomenda **cancelada** aparece ao cliente como "EM PRODUÇÃO", com botão
  "Repetir Pedido" e sem qualquer indicação do cancelamento.
- Encomenda **em suspenso (WIP hold)** aparece como se estivesse a avançar.
- Uma fase chamada, por exemplo, "Concluir montagem" faz a encomenda passar a
  "CONCLUÍDO" e a oferecer **Certificado de Conformidade** de um produto que
  ainda está na linha — é o mesmo bug (b) do `BUGS_RESOLVIDOS.md`, reintroduzido
  aqui por comparação de strings.

**Correção:** usar `EstadoOrdem.derivar(...)` (`lib/models/estado_ordem.dart`),
que já é a definição única do estado, e incluir as colunas no `select`.

#### Resolução (2026-08-01)

- `PortalClienteRepository.obterEncomendas()` traz `cancelada`,
  `motivo_cancelamento` e `em_suspenso`, e devolve `EncomendaModel` — cujo
  getter `estado` já delega em `EstadoOrdem.derivar`. A comparação de strings
  sobre o nome da fase desapareceu do portal.
- O histórico mostra os quatro estados com cor e ícone próprios, incluindo
  **CANCELADA** (a vermelho, com o motivo quando existe) e **ON HOLD**. Só em
  produção é que o badge mostra o nome da fase, que é aí a informação útil.
- O **Certificado de Conformidade** passou a estar disponível apenas com
  `EstadoOrdem.concluida`. Antes bastava uma fase chamada "Concluir montagem"
  para o cliente descarregar um certificado de um produto ainda na linha.
- O rastreio recebe os mesmos dois campos da função no servidor e mostra o
  mesmo badge; uma ordem suspensa mostra a fase em curso como *"Suspensa"* em
  vez de *"Em Processamento"*.

### (C) O rastreio expõe encomendas e nomes de outros clientes — ✅ resolvido

`rastreio_cliente_screen.dart:38-50` pesquisa por `codigo_rastreio` **sem
qualquer filtro por cliente**, e devolve `clientes ( nome_cliente )`. Qualquer
pessoa com um código (ou que os adivinhe — o formato `TRC-XXXXXX` é enumerável)
vê o artigo, a data de entrega e **o nome do cliente destinatário**.

Agrava-se com dois factos já conhecidos:
- o ecrã está acessível **sem autenticação** a partir do `login_screen.dart:260`;
- o RLS está desativado e o papel `anon` tem acesso total (observação 106 do
  histórico de sessões).

**Correção:** decidir o modelo. Se o rastreio público é requisito de negócio,
tem de passar por uma função `SECURITY DEFINER` que devolva apenas
`{fase, data_entrega}` sem identificar o cliente. Se não é, filtrar por
`cliente_id` do utilizador autenticado. Em qualquer dos casos, RLS ligado.

#### Resolução (2026-08-01)

**Decisão:** o rastreio continua público — é requisito de negócio — mas passa a
ser anónimo.

- Migração `rastreio_publico_anonimo`: função
  `public.rastrear_encomenda(p_codigo text)`, `SECURITY DEFINER` com
  `search_path = public`, `EXECUTE` revogado a `public` e concedido apenas a
  `anon` e `authenticated`. Devolve `codigo_rastreio`, `data_entrega`,
  `nome_tipo_produto`, `fase_atual_id`, `cancelada`, `em_suspenso` e o roteiro
  de fases. **Nunca** devolve cliente, observações nem motivo de cancelamento.
- Comparação do código insensível a maiúsculas e a espaços, o que também
  corrige pesquisas legítimas que falhavam por causa de um espaço colado.
- `rastreio_cliente_screen.dart` deixou de consultar a tabela `encomendas`:
  chama `PortalClienteRepository.rastrear()`, que devolve `RastreioEncomenda` —
  um modelo que **não tem sequer um campo** onde guardar o cliente. O modelo
  fecha a porta a uma regressão futura.
- Um teste (`test/repositories/portal_cliente_repository_test.dart`) fixa esse
  contrato.

Fica por fazer, por decisão explícita: **ligar o RLS**. É transversal aos três
módulos e será feito no fim da vistoria, para que qualquer erro que apareça a
seguir seja atribuível a essa alteração e não a esta. Até lá, a função reduz a
exposição mas o acesso direto às tabelas continua aberto ao papel `anon`.

### (D) `historico_cliente_screen` fica preso no estado de erro — ✅ resolvido

`_carregarHistorico` (linha 29) nunca faz `_erro = null` no início. O botão de
refresh (linhas 264-270) só põe `_isLoading = true`. Depois de uma única falha
de rede, **o ecrã mostra o erro para sempre**, mesmo quando os recarregamentos
seguintes têm sucesso — a única saída é o cliente fazer logout.

#### Resolução (2026-08-01)

- `_carregarHistorico()` passou a começar por `_erro = null` e
  `_isLoading = true`, pelo que é a própria função a definir o estado de
  entrada — o botão de refresh limita-se a chamá-la.
- O estado de erro deixou de ser um texto solto no centro do ecrã e passou a ter
  ícone, mensagem e **botão "Tentar novamente"**, sem obrigar o cliente a
  procurar o ícone de refresh no cabeçalho.
- O mesmo padrão foi aplicado ao arranque do ecrã de pedido
  (`solicitar_encomenda_screen.dart`), que antes engolia a falha de carregamento
  e mostrava um formulário vazio sem explicação.

### (E) `setState` após `dispose` no rastreio — ✅ resolvido

`rastreio_cliente_screen.dart:52-77`: três `setState` depois de `await`, nenhum
protegido por `if (mounted)`. Sair do separador durante uma pesquisa lenta lança
`setState() called after dispose()`. Os outros ecrãs do portal têm a guarda; este
não.

#### Resolução (2026-08-01)

- Todos os `setState` a seguir a um `await` no portal passam por
  `if (!mounted) return;`. O ecrã de rastreio ficou com um único ponto de
  atualização, no fim de `_buscarRastreio()`, em vez dos três caminhos de saída
  que existiam.
- A "encomenda não encontrada" deixou de ser um `return` a meio da função e
  passou a ser o `null` devolvido pelo repositório, tratado no mesmo `setState`
  — um estado, um sítio.

### (F) Dropdown rebenta se o produto repetido já não existir — ✅ resolvido

`historico_cliente_screen.dart:416-426` envia `tipos_produtos_id` para
`preencherParaRepeticao`, que faz `_tipoProdutoSelecionadoId = tipoProdutoId`
(`solicitar_encomenda_screen.dart:39-44`) sem verificar se esse id ainda está em
`_tiposProduto`. O `DropdownButtonFormField` dispara a asserção
*"There should be exactly one item with [DropdownButton]'s value"* e o ecrã fica
em écran vermelho. Acontece sempre que um tipo de produto é desativado ou
removido no painel admin.

Nota relacionada: o callback é declarado `Function(int, int)` mas o valor é
convertido para `String` no shell (`cliente_shell_screen.dart:397`) — o tipo
atravessa `int → String → int` sem razão.

#### Resolução (2026-08-01)

- `preencherParaRepeticao` recebe agora `int` e **valida o artigo contra a lista
  carregada** antes de o atribuir ao dropdown. Artigo já indisponível: a
  seleção não muda e o cliente recebe a mensagem *"O artigo dessa encomenda já
  não está disponível. Selecione outro da lista."* — em vez do ecrã vermelho.
- O pedido de repetição feito antes de a lista estar carregada fica guardado em
  `_repeticaoPendente` e é aplicado (e validado) no fim do carregamento. Antes,
  a corrida entre o toque no histórico e o `_carregarDadosIniciais` podia perder
  o artigo escolhido.
- `_carregarDadosIniciais` também deixa cair uma seleção que tenha entretanto
  deixado de existir, em vez de a manter num dropdown que já não a tem.
- O tipo `int` deixou de dar a volta por `String`: o callback, o modelo e a
  coluna usam todos o mesmo tipo. O botão "Repetir Pedido" fica desativado se a
  encomenda não tiver artigo associado.
- O dropdown mantém o parâmetro `value`, deprecado a favor de `initialValue`,
  com `// ignore: deprecated_member_use` e a razão escrita no código:
  `initialValue` só é lido na construção do campo, pelo que a repetição a partir
  do histórico deixaria de conseguir mudar a seleção. Fica para a migração de
  deprecações de todo o repositório.

---

## 2. Bugs de segundo nível — ✅ resolvida (2026-08-02)

1. **Notificações repetidas.** `cliente_shell_screen.dart:92-113`: o
   `.stream()` reemite a **lista completa** a cada alteração; o `for` mostra um
   SnackBar por cada linha com `lida == false`. Uma notificação nova provoca
   SnackBars repetidos das anteriores ainda não marcadas. Falta um `Set` de ids
   já apresentados.

   ✅ **Resolução:** o shell mantém `_notificacoesApresentadas`, um `Set` de ids
   mostrados nesta sessão; `Set.add` devolve `false` para um id repetido, o que
   serve de guarda numa linha. O stream passou para
   `PortalClienteRepository.escutarNotificacoes()`, com o `try/catch` à volta da
   subscrição substituído pelo `onError` do próprio `listen` — o `try` anterior
   nunca apanhava nada, porque a falha chega pelo stream e não pela chamada.
2. **Marcação de lida sem await nem tratamento de erro.** Linha 143:
   `_supabase.from('notificacoes').update({'lida': true}).eq('id', ...)` é
   *fire-and-forget*. Se falhar, a notificação volta na emissão seguinte —
   combinado com o ponto 1, dá um ciclo de SnackBars.

   ✅ **Resolução:** `marcarNotificacaoLida()` é agora esperada com `await` e a
   falha é registada. **Decisão:** o id fica no `Set` mesmo quando a marcação
   falha. A alternativa — retirá-lo para tentar de novo — recria exatamente o
   ciclo de SnackBars que se está a corrigir. O custo é a notificação continuar
   marcada como não lida na base de dados e reaparecer na sessão seguinte, que é
   o comportamento menos mau dos dois.
3. ~~**Erros técnicos mostrados ao cliente.**~~ ✅ resolvido com os bugs
   críticos: os quatro ecrãs passaram a apanhar `RepositoryException` e a
   mostrar `e.mensagem`. O `$e` cru — que expunha nomes de tabelas e colunas —
   desapareceu do portal.
4. **Avaliação duplicável.** `historico:181` insere em `avaliacoes` sem
   restrição única `(encomenda_id, cliente_id)` na base de dados; dois toques
   rápidos ou dois separadores dão duas avaliações da mesma encomenda. A
   verificação atual é só do lado do cliente (`_encomendasAvaliadasIds`).

   ✅ **Resolução:** migração `avaliacao_unica_por_encomenda_e_cliente` — índice
   único `avaliacoes_encomenda_cliente_key (encomenda_id, cliente_id)`. Não
   havia duplicados a limpar. `registarAvaliacao()` reconhece o código `23505`
   e devolve *"Esta encomenda já foi avaliada."* em vez do texto do Postgres.
   Foi preciso ensinar `BaseRepository.guarda` a **deixar passar** uma
   `RepositoryException` já traduzida: o `catch` final estava a trocá-la pela
   mensagem genérica. Coberto por `test/repositories/base_repository_test.dart`.
5. ~~**`comentario` vazio gravado como `''`.**~~ ✅ resolvido. Verificação no
   servidor desmentiu a justificação que estava escrita no código
   (`"resolvendo a restrição NOT NULL"`): `avaliacoes.comentario` **é
   anulável**. O repositório grava `NULL` quando o campo fica vazio, pelo que
   "avaliações com comentário" passa a ser contável.
6. ~~**`data_registo` calculada no cliente.**~~ ✅ resolvido. A coluna já tinha
   `DEFAULT CURRENT_DATE`; bastou deixar de a enviar. A data deixa de depender
   do relógio do dispositivo.
7. **Sem paginação no histórico.** `historico:63-76` carrega *todas* as
   encomendas do cliente de uma vez. `PaginaResultado` e `tamanhoPaginaPadrao`
   já existem em `lib/core/paginacao.dart` e são usados nos outros módulos.

   ✅ **Resolução:** `obterEncomendas()` aceita `deslocamento`/`tamanho`, pede
   uma linha-sentinela a mais e devolve `PaginaResultado` — o mesmo mecanismo
   dos outros módulos, sem uma segunda query de `count`. O ecrã mostra
   *"Carregar mais encomendas"* enquanto houver páginas. Um recarregamento
   **repõe tudo o que já estava visível**, e não apenas a primeira página: com
   realtime ligado, colapsar a lista a cada avanço de fase faria o cliente
   perder o scroll a meio da leitura.
8. **Sem realtime no histórico e no rastreio.** O cliente tem de carregar em
   refresh para ver a fase mudar, apesar de o texto do ecrã prometer
   *"acompanhar o estado do seu pedido em tempo real"*
   (`rastreio_cliente_screen.dart:112`). O `lib/core/realtime.dart` já existe.

   ✅ **Resolução:** `escutarAtividadeDoCliente()` subscreve `encomendas` e
   `pedidos_encomenda`; os dois ecrãs recarregam com 400 ms de espera, para que
   o avanço de uma fase — que escreve em mais do que uma tabela — dê uma única
   leitura em vez de três. No rastreio a atualização é **silenciosa**: não apaga
   o cartão nem pisca o indicador de progresso, e uma falha de rede a meio é
   registada no log em vez de substituir por um erro o cartão que o cliente tem
   à frente. Os canais são removidos no `dispose`. A promessa de "tempo real"
   voltou ao subtítulo do rastreio, agora que é verdade.
9. **`Text` com valor possivelmente nulo.** `rastreio:195`
   `Text(_encomenda!['codigo_rastreio'])` — `dynamic` a entrar num parâmetro
   `String`; se a coluna vier nula é `TypeError` em runtime. O mesmo ecrã já
   trata `nome_tipo_produto` com `?? 'Artigo'`.
10. **Layout rebenta em ecrã estreito.** `historico:313-435`: `Row` com título,
    badge e três botões sem `Wrap` nem `LayoutBuilder`, dentro de um
    `Padding(40)` fixo. Em tablet/telemóvel dá *RenderFlex overflow*. O portal é
    o módulo com maior probabilidade de ser aberto no telemóvel.
    ✅ **Resolução:** badges e grupos de botões passaram a `Wrap`; abaixo de
    760 px de largura o cartão passa de `Row` a `Column` (ações debaixo da
    identificação) e o `Padding` desce de 40 para 16, com o título a acompanhar.
    Deixa de haver *RenderFlex overflow* em telemóvel.
11. **O cliente não vê os pedidos que submeteu.** `solicitar_encomenda` insere em
    `pedidos_encomenda` e nunca mais mostra nada. O cliente não sabe se o pedido
    ficou Pendente, foi aprovado ou rejeitado — e não tem forma de saber que já
    submeteu, pelo que volta a submeter. Falta a lista de pedidos com estado.

    ✅ **Resolução:** secção **"Os Meus Pedidos"** por baixo do formulário, a
    partir de `obterMeusPedidos()` — cada pedido com artigo, quantidade, data de
    submissão, observações e badge de estado (`EstadoPedido`: Pendente,
    Aprovado, Em Produção, Rejeitado), com a nota *"A aguardar análise da nossa
    equipa"* enquanto estiver pendente. A lista é relida logo a seguir a uma
    submissão bem sucedida, para o cliente ver imediatamente o que acabou de
    enviar.

---

## 3. Dívida arquitetural (face ao `dashboard_admin` e ao `terminal_operador`)

1. **Sem camada de repositório.** Os 4 ecrãs instanciam
   `Supabase.instance.client` e escrevem SQL/PostgREST inline. Falta um
   `ClientePortalRepository` (ou métodos novos em `ClientesRepository` /
   `EncomendasRepository`) sobre `BaseRepository.guarda`.
2. **Sem modelos de domínio.** Tudo é `Map<String, dynamic>` e `List<dynamic>`,
   com conversões defensivas repetidas oito vezes:
   `x is int ? x : int.parse(x.toString())`. Existem já `EncomendaModel`,
   `ClienteModel`, `PedidoModel`, `EstadoOrdem`.
3. **`obterIniciais` duplicado.** `cliente_shell_screen.dart:147-155`
   reimplementa `lib/core/iniciais.dart`, com bug próprio: `partes[1]` não
   tolera espaços duplos (o de `core` usa `RegExp(r'\s+')`).
4. **`_formatarData` duplicado.** Idêntico em `historico:222` e `rastreio:80`;
   `Formatos.dataHora` já existe e converte para hora local (estes dois não
   fazem `toLocal()`, pelo que uma data à noite pode aparecer com o dia errado).
5. **Cores hardcoded.** `Colors.deepPurple`, `Color(0xFFF8FAFC)`,
   `Color(0xFF0F172A)`, `Color(0xFF111625)` espalhados pelos 4 ficheiros, em vez
   de `TemasCores`. Além disso, o portal é o único módulo roxo — os outros dois
   seguem a paleta partilhada.
6. **SnackBars manuais.** Nenhum uso de `MensagensContexto.mostrarMensagem`,
   apesar de a extensão existir exactamente para isto.
7. **Sem `EcraRecarregavel`.** O shell usa `IndexedStack`
   (`cliente_shell_screen.dart:435`), portanto os separadores ficam vivos e os
   dados congelam ao trocar de separador — o mesmo problema que motivou a
   interface no terminal do operador. Só o histórico tem botão de refresh
   manual.
8. **"Código do Cliente" inventado.** `cliente_shell_screen.dart:276` e `518`:
   `'CLI-2026-${nome.hashCode.abs().padLeft(4,'0').substring(0,4)}'`. Três
   defeitos num só: o ano está fixo em 2026 (o mesmo bug que `Formatos`
   resolveu), `hashCode` de String não é estável entre plataformas (web vs
   nativo) nem garantido entre versões, e o `substring(0,4)` de um número longo
   dá colisões entre clientes diferentes. O identificador real —`clientes.id`—
   está disponível e não é usado. A expressão está ainda duplicada em dois
   sítios.
9. **`withOpacity` deprecado.** Linhas 484, 533, 572 — substituir por
   `withValues(alpha: ...)`, alinhando com a limpeza dos avisos do `analyze`
   (observação 166).

---

## 3b. O que a correção dos bugs críticos já trouxe da secção 3

Resolver (A), (B) e (C) sem tocar na arquitetura era impossível — as três
correções vivem na camada de dados. Ficaram feitos:

- **Ponto 1 (repositório):** `lib/repositories/portal_cliente_repository.dart`,
  sobre `BaseRepository.guarda`. Os quatro ecrãs deixaram de instanciar
  `Supabase.instance.client`.
- **Ponto 2 (modelos):** o histórico usa `EncomendaModel` e `ClienteModel`; o
  rastreio usa `RastreioEncomenda`/`FaseRoteiro`; o formulário usa
  `TipoProdutoOpcao`. As oito conversões
  `x is int ? x : int.parse(x.toString())` desapareceram.

A correção da secção 2 fechou mais dois:

- **Ponto 7 (`EcraRecarregavel`):** implementado por `HistoricoClienteScreenState`.
  Falta o shell chamá-lo ao trocar de separador — com o realtime ligado, a
  urgência caiu, porque a lista já se atualiza sozinha.
- **Paginação e realtime** (pontos 7 e 8 da secção 2) ficaram feitos.

Continuam por fazer: `obterIniciais` (3) e `_formatarData` (4) duplicados, cores
hardcoded (5), `MensagensContexto` (6), a ligação do `EcraRecarregavel` ao shell
(7), o "Código do Cliente" derivado de `hashCode` (8) e as três chamadas a
`withOpacity` (9) — os únicos avisos que o `flutter analyze` ainda dá no módulo,
todos no `cliente_shell_screen.dart`.

## 4. Testes

`test/` contém `models/`, `repositories/` e `widgets/` — **nada do portal do
cliente**. Depois de introduzida a camada de repositório, os alvos mínimos são:

✅ **Feito:**

- `test/repositories/portal_cliente_repository_test.dart` (2026-08-01) — 8
  testes sobre `RastreioEncomenda` e `TipoProdutoOpcao`: localização da fase em
  curso, roteiro alterado depois do lançamento da ordem, roteiro vazio,
  derivação de estado com `cancelada`/`em_suspenso` e a garantia de que a
  resposta do rastreio não traz o cliente.
- `test/repositories/base_repository_test.dart` (2026-08-02) — 3 testes sobre
  `guarda`, incluindo o que impede a mensagem *"Esta encomenda já foi
  avaliada."* de voltar a ser engolida pelo `catch` genérico.

Suite completa: **194 testes a passar**. `flutter analyze` do módulo sem erros
(só as três deprecações de `withOpacity`).

Restantes alvos:

- resolução do cliente autenticado (com e sem registo associado);
- derivação do estado da encomenda no histórico (cancelada, suspensa, concluída,
  em produção);
- acumulação de páginas no histórico e reposição no recarregamento.

---

## 5. Ordem de execução proposta

**Fase 1 — dados e segurança (bloqueia tudo o resto)**
1. ✅ (A) identidade por `clientes.utilizador_id` + migração dos dados por nome.
2. ✅ (C) rastreio público mas anónimo, via `rastrear_encomenda`.
   ⬜ RLS nas tabelas que o portal lê (`encomendas`, `clientes`, `avaliacoes`,
   `pedidos_encomenda`, `notificacoes`) — adiado por decisão para o fim da
   vistoria.
3. ✅ Restrição única em `avaliacoes(encomenda_id, cliente_id)` (ponto 4 da
   secção 2). O `data_registo` já estava resolvido no servidor.

**Fase 2 — correções funcionais**
4. ✅ (B) `EstadoOrdem` no histórico e no rastreio, com `cancelada`/`em_suspenso`
   no `select`.
5. ✅ (D) limpar `_erro` no recarregamento; (E) guardas `mounted`; (F) validar o
   id do produto antes de o pôr no dropdown.
6. ✅ Notificações: deduplicação por id e `await` na marcação de lida.

**Fase 3 — arquitetura**
7. ✅ `PortalClienteRepository` + modelos, retirando o Supabase dos widgets.
8. 🟡 `PaginaResultado`, `realtime` e `EcraRecarregavel` (por ligar ao shell)
   feitos. Faltam `Formatos`, `obterIniciais`, `TemasCores` e
   `MensagensContexto`.
9. ⬜ Código do cliente real (`clientes.id`) em vez do derivado de `hashCode`.

**Fase 4 — UX**
10. ✅ Layout responsivo do histórico; mensagens de erro de negócio; lista de
    pedidos submetidos com o respetivo estado.

**Fase 5 — testes**, conforme a secção 4.

---

## 6. O que falta, depois das secções 1 e 2

Tudo o que resta está concentrado num único ficheiro,
`cliente_shell_screen.dart`, e na base de dados:

1. **RLS** — adiado por decisão para o fim da vistoria.
2. **Dívida arquitetural do shell** — pontos 3, 4, 5, 6, 8 e 9 da secção 3:
   `obterIniciais` e `_formatarData` duplicados, cores hardcoded,
   `MensagensContexto`, o "Código do Cliente" derivado de `hashCode` e as três
   deprecações de `withOpacity`.
3. **Ligar o `EcraRecarregavel` ao shell** (ponto 7 da secção 3) — a interface
   já está implementada do lado do histórico.
4. **Testes** dos alvos que restam na secção 4.

Só depois desta sequência faz sentido acrescentar funcionalidades novas ao
portal: quase todas elas (notificações fiáveis, faturas, anexos, chat com a
produção) assentam na identidade correta do cliente, que hoje não existe.
