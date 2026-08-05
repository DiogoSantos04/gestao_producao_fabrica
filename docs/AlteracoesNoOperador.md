# Revisão do módulo `terminal_operador`

> Documento de **diagnóstico**, não de alterações já feitas. Regista o estado da
> pasta `lib/screens/terminal_operador/` após o refactor concluído em
> `dashboard_admin` (ver [ARQUITETURA_REFACTOR.md](ARQUITETURA_REFACTOR.md),
> [BUGS_RESOLVIDOS.md](BUGS_RESOLVIDOS.md), [NotasDeAlteracoes.md](NotasDeAlteracoes.md)).
>
> Data da revisão: 2026-07-31. Baseline: commit `75e970e`.

## Estado das correções

| Bug | Estado |
|:---|:---|
| (A) `_concluirFase` sem RPC transacional | ✅ resolvido |
| (B) Incidência não suspende a ordem | ✅ resolvido |
| (C) Histórico corrompido por registo falso | ✅ resolvido |
| (D) Motivos de paragem hardcoded | ✅ resolvido |
| (E) Fila mostra ordens não trabalháveis | ✅ resolvido |
| Secção 2 (13 bugs de segundo nível) | ✅ resolvida |
| Secção 3 (dívida arquitetural) | ✅ resolvida |
| Secção 4 (terminal de fábrica) | parcial — falta ergonomia, QR, offline, acessibilidade |
| RLS e privilégios | adiado por decisão — **último passo** |

Secção 1 fechada e verificada contra a base de dados: permissões das RPCs
confirmadas e zero registos corrompidos por (C) — detalhes abaixo.

O achado de segurança (RLS desligada, `anon` com escrita total) mantém-se em
aberto **por decisão**: nenhuma tabela do projeto tem RLS ativa, pelo que a
ativar-se é um trabalho transversal a toda a aplicação e não só a este módulo.
Fica para o fim, depois de todo o resto estar fechado.

## Contexto

6 ficheiros, ~2.100 linhas no início da revisão:

| Ficheiro | Antes | Depois |
|:---|---:|---:|
| `detalhe_tarefa_screen.dart` | 807 | 838 |
| `historico_operador_screen.dart` | 546 | 590 |
| `operador_shell_screen.dart` | 622 | 677 |
| `fila_trabalho_screen.dart` | 390 | 388 |
| `relatorios_operador_screen.dart` | 273 | 344 |
| `popups/bloquear_tarefa_screen.dart` | 214 | 343 |
| `repositories/operador_repository.dart` | — | 514 (novo) |

Diagnóstico inicial: **a pasta tinha ficado congelada no estado pré-refactor**.
Nenhum dos 6 ficheiros usava `lib/repositories/`, `lib/models/`, `lib/core/` ou
`lib/widgets/`. Agravava-se por conterem as duas escritas mais críticas de toda
a aplicação — avançar de fase e bloquear produção — e ambas estarem erradas.

A contagem subiu, e é o resultado esperado: o que se acrescentou foram estados
de erro visíveis, confirmações, paginação e documentação das decisões — coisas
que antes não existiam. O que saiu foram as queries, que passaram para o
repositório, e `lib/services/producao_service.dart` (156 linhas de código morto
com uma segunda implementação do avanço de fase), eliminado.

---

## 1. Bugs críticos de negócio

### (A) `_concluirFase` não usa a RPC transacional — ✅ resolvido

`detalhe_tarefa_screen.dart:382-433` faz duas chamadas separadas: `insert` em
`historico_producao` seguido de `update` em `encomendas`. Uma falha entre as duas
deixa um registo de histórico órfão com a ordem parada na mesma fase.

Existe `EncomendasRepository.avancarFase()` (RPC `avancar_fase_encomenda`,
transacional, `SECURITY INVOKER`) já usada pelo admin. O ecrã reimplementa em
Dart a regra "próxima fase = índice + 1" — exatamente a classe de divergência
que originou o bug (b) dos relatórios no admin.

**Resolução (2026-07-31).** Ficheiro `detalhe_tarefa_screen.dart`. As duas
escritas separadas deram lugar a uma chamada a
`EncomendasRepository.avancarFase(widget.encomendaId)`. O servidor decide a fase
seguinte, escreve o histórico e atualiza a ordem numa só transação — deixa de
haver janela para um registo órfão — e recusa o avanço se a ordem estiver em WIP
Hold ou cancelada, validações que o cliente não conseguia garantir sozinho. O
cálculo local de `proximaFaseId` foi eliminado, pelo que a regra passa a existir
num só sítio.

Alterações de apoio, no mesmo ficheiro:

- A mensagem de sucesso passa a usar o retorno da RPC (`concluida`,
  `proxima_fase_nome`): distingue "ordem finalizada" de "avançou para \<fase\>",
  em vez do texto único de antes.
- A chave do cronómetro (`_temposInicioFase`) só é removida **depois** de a
  transição passar. Antes era removida antes das escritas: se estas falhassem, o
  tempo acumulado da fase perdia-se na mesma.
- Erros traduzidos por `RepositoryException` (`_limparErro`), de modo a mostrar
  ao operador o texto de negócio das RPCs (ex: *"Encomenda em WIP Hold: aprove o
  Line Clearance antes de avançar."*) em vez do erro do driver.
- Em caso de falha o ecrã recarrega. O estado no servidor pode ter mudado
  entretanto (hold aplicado por outra via, ordem cancelada) e o operador ficaria
  a olhar para uma fase que já não é a atual.

Nota: o `static Map _temposInicioFase` continua a ser o mecanismo do cronómetro.
É defeito próprio, listado na secção 2, e não faz parte de (A).

### (B) Reportar incidência não bloqueia produção — ✅ resolvido

`popups/bloquear_tarefa_screen.dart:42-82` insere em `incidencias` mas **nunca
escreve `encomendas.em_suspenso = true`**. O botão chama-se "Bloquear Produção"
e a ordem continua a fluir para o admin e para os postos seguintes.

A RPC `aplicar_wip_hold` (`EncomendasRepository.aplicarWipHold`) faz a operação
completa e transacionalmente.

**Resolução (2026-07-31).** As duas escritas soltas deram lugar a uma única
chamada a `EncomendasRepository.aplicarWipHold(...)` — a mesma RPC que o painel
de controlo do admin usa desde o refactor. A RPC escreve
`encomendas.em_suspenso = true` dentro da transação, pelo que o botão "Bloquear
Produção" passa efetivamente a bloquear: a ordem deixa de fluir para os postos
seguintes e aparece em hold no painel do admin.

### (C) A mesma função corrompe o histórico de produção — ✅ resolvido

Para obter um `historico_producao_id` a que ligar a incidência, insere um registo
com `data_conclusao = agora` para uma fase que **não foi concluída**.
Consequências em cadeia:

- `historico_operador_screen` apresenta a fase como executada;
- `relatorios_operador_screen` conta-a em "Fases Superadas";
- o PDF de turno e as métricas de produtividade do admin ficam inflados.

**Resolução (2026-07-31).** O `insert` em `historico_producao` foi eliminado do
ecrã. A ligação entre incidência e histórico é agora resolvida no servidor, pela
RPC, a partir da fase atual da encomenda — deixa de se marcar como concluída uma
fase que foi interrompida. As contagens do histórico do operador, dos relatórios
de turno e das métricas do admin deixam de ser inflacionadas.

✅ **Dados históricos verificados (2026-07-31).** Query de diagnóstico corrida
contra a base de dados de produção:

```sql
select count(*) from historico_producao h
where exists (select 1 from incidencias i where i.historico_producao_id = h.id);
```

Resultado: **0 registos**, em 5 linhas de `historico_producao` e 3 de
`incidencias` — nenhuma incidência tem `historico_producao_id` preenchido.
Confirmado também que não há duplicados `(encomenda_id, fase_concluida_id)`.
Não há dados corrompidos a limpar: o defeito existia no código mas nunca chegou
a ser exercido com volume. **Nada a fazer.**

### (D) Motivos de paragem hardcoded — ✅ resolvido

Lista de 5 strings em Dart, concatenadas em `'[$motivo] $observações'` num único
campo de texto livre. A base de dados tem a tabela `reason_codes`
(`EncomendasRepository.obterReasonCodes()`), usada pelo admin. Sem códigos
estruturados, análise de Pareto das paragens é impossível.

**Resolução (2026-07-31).** A lista em Dart deu lugar aos motivos oficiais lidos
por `obterReasonCodes()`, com deduplicação por `id` antes de alimentar o
dropdown (o `DropdownButtonFormField` lança em runtime com dois itens de igual
valor — mesma precaução que o painel de controlo já tomava). O `reason_code_id`
passa a ser gravado como chave estrangeira e as observações do operador vão para
o campo próprio (`descricao_operador`), em vez de serem concatenadas no texto.

Não foi alargamento de âmbito: a assinatura da RPC exige `p_reason_code_id`,
portanto (D) era requisito de (B).

### Notas comuns às correções da secção 1

Ficheiros tocados: `popups/bloquear_tarefa_screen.dart` (reescrito, 214 → 310
linhas), `detalhe_tarefa_screen.dart`, `fila_trabalho_screen.dart`.

(B), (C) e (D) viviam na mesma função de 40 linhas e foram corrigidos em
conjunto. Alterações de apoio no popup:

- Estados de carregamento e de falha visíveis no campo de motivo, com botão
  "Tentar de novo". Uma falha de rede a ler `reason_codes` não pode passar por
  "não há motivos": sem motivo não há bloqueio possível. O botão de submissão
  fica desativado enquanto não houver motivos carregados.
- Erros traduzidos por `RepositoryException` (`_limparErro`), como nos ecrãs
  admin, em vez de `'Erro ao bloquear: $e'` com o texto do driver.
- `_isSaving` volta a `false` apenas no ramo de erro — antes o `finally` fazia
  `setState` mesmo depois do `pop`, sobre um widget desmontado.
- Depreciação corrigida: `DropdownButtonFormField.value` → `initialValue`.
- Typo corrigido: `'detalhe o problem.'` → `'detalhe o problema.'` (secção 2).

**Verificação:** `flutter analyze lib/screens/terminal_operador` — **0 issues**
no ficheiro alterado. As 8 restantes são pré-existentes nos outros ficheiros da
pasta e constam da secção 2. Reconfirmado após (A) e (E): continuam a ser as
mesmas 8, nenhuma introduzida.

**Por validar manualmente** (cobre a secção 1 inteira, ciclo completo num só
percurso):

1. Reportar uma incidência no terminal — o dropdown apresenta os reason codes
   reais e as observações são aceites.
2. A ordem passa a aparecer em WIP Hold no painel do admin, e **não** surge uma
   nova linha no histórico do operador.
3. De volta à fila do operador: a ordem aparece com `ON HOLD` e o botão diz
   "Aguarda Line Clearance", desativado.
4. Aprovar o Line Clearance no admin — a ordem volta a ser iniciável.
5. Concluir a fase — a mensagem indica a fase seguinte pelo nome (ou "ordem
   finalizada" na última) e o histórico regista exatamente uma linha.
6. Tentar concluir uma fase de uma ordem posta em hold entretanto — deve
   aparecer a mensagem de negócio da RPC, não um erro do driver.
7. Confirmar que uma ordem cancelada não aparece na fila.

✅ **Permissões confirmadas (2026-07-31).** As três RPCs
(`avancar_fase_encomenda`, `aplicar_wip_hold`, `aprovar_line_clearance`) são de
facto `SECURITY INVOKER` (`prosecdef = false`) e têm `EXECUTE` concedido a
`anon` e `authenticated`. Como são invoker, o acesso efetivo depende dos
privilégios de tabela: `encomendas`, `historico_producao`, `incidencias` e
`reason_codes` dão `arwdDxtm` a `authenticated`. Logo, o perfil operador executa
as RPCs sem erro de permissão. (A) e (B) não rebentam em runtime.

⚠️ **Efeito lateral desta verificação — segurança.** As mesmas queries mostram
`relrowsecurity = false` em todas as tabelas do módulo, e privilégios totais
para `anon` (não só `authenticated`). Ou seja: qualquer detentor da chave
pública lê e escreve a tabela inteira, sem passar pelas RPCs. Isto confirma e
agrava o ponto "Autorização a sério" da secção 4 — o controlo de negócio vive
nas RPCs, mas nada obriga a passar por elas. É a prioridade seguinte depois da
secção 2.

### (E) A fila mostra ordens que não são trabalháveis — ✅ resolvido

`fila_trabalho_screen.dart:77-88` filtra apenas por `fase_atual_id`. Não exclui
`cancelada` nem `em_suspenso`. O operador vê — e pode iniciar — uma ordem
cancelada ou em WIP Hold. `EstadoOrdem` já define a precedência correta
(cancelada → em hold → concluída → em produção).

**Resolução (2026-07-31).** Tratamento diferente para os dois casos, por serem
situações diferentes para quem está no posto:

- **Canceladas:** excluídas no servidor, com `.eq('cancelada', false)` na query.
  Não há nada a fazer com elas e não devem ocupar espaço na fila.
- **Em WIP Hold:** continuam visíveis, mas marcadas com a etiqueta `ON HOLD` e
  com o botão desativado, a ler "Aguarda Line Clearance". Escondê-las deixaria o
  operador sem saber para onde foi o trabalho que estava a fazer; o que não pode
  é poder iniciá-las.

O estado passa a ser derivado por `EstadoOrdem.derivar(...)` — a definição única
partilhada com o admin — em vez das regras próprias deste ecrã. "Atrasado" e "Em
Progresso" mantêm-se como leitura operacional, mas só se aplicam a uma ordem que
esteja mesmo em produção: antes, uma ordem em hold com entrega vencida aparecia
como "Atrasado", escondendo o motivo real da paragem.

As colunas `cancelada` e `em_suspenso` foram acrescentadas ao `select`, que não
as trazia.

---

## 2. Bugs de segundo nível — ✅ resolvida (2026-07-31)

| Local | Problema | Estado |
|:---|:---|:---|
| `detalhe_tarefa_screen.dart:32` | `static final Map _temposInicioFase` — global, partilhado entre utilizadores, nunca limpo (cresce toda a sessão), perde-se em restart. O cronómetro de produção devia ler uma coluna `data_inicio_fase` escrita pela RPC. | ✅ |
| `detalhe_tarefa_screen.dart:536-538` | "Dimensões: 500mm x 300mm x 150mm" e "Material: Aço Inoxidável 304" **hardcoded**. Dados falsos apresentados ao operador no chão de fábrica. | ✅ |
| `detalhe_tarefa_screen.dart:104-153` | Três fallbacks encadeados a adivinhar o nome da coluna (`tipos_produto_id` / `tipos_produtos_id` / `tipo_produto_id`), cada um com `try/catch` silencioso. O schema é conhecido: são 3 round-trips e ruído que esconde erros reais. | ✅ |
| `fila_trabalho_screen.dart:99` | `final int tipoProdutoId = enc['tipos_produtos_id'];` sem verificação de nulo — `TypeError` em qualquer encomenda sem tipo de produto. | ✅ |
| `fila_trabalho_screen.dart:120` | `(ordemAtual - 1) / totalFases` assume `ordem` contígua a começar em 1 e nunca atinge 100%. | ✅ |
| `fila_trabalho_screen.dart:91-94` | Carrega **toda** a tabela `fases_padrao`, sem filtro, para calcular o progresso em memória. 4 round-trips por recarregamento. | ✅ |
| `relatorios_operador_screen.dart:31` | `if (user == null) return;` deixa `_isLoading = true` — spinner infinito. | ✅ |
| `relatorios_operador_screen.dart:81` | `setState` sem `if (mounted)` no caminho de sucesso. | ✅ |
| `relatorios_operador_screen.dart:60` | `data.isAfter(inicioMes)` exclui os registos do dia 1 às 00:00. Deve ser `!isBefore`. | ✅ |
| `historico_operador_screen.dart:195` | `setState` dentro de `setState` — `_filtrarEReordenarResultados()` é chamado de dentro do `setState` de `_carregarHistorico`. | ✅ |
| `historico_operador_screen.dart:442` | `incidencias.first['motivo']` — ignora as restantes incidências do registo. | ✅ |
| `operador_shell_screen.dart:438,512` | `'EMP-2026-' + nome.hashCode` — ID de funcionário fabricado, com ano fixo, que muda se o nome mudar. Mesmo defeito que `Formatos.referenciaOrdem` já corrigiu no admin. Deve usar `utilizador_id`. | ✅ |
| `operador_shell_screen.dart:494` | "Terminar Sessão" sem diálogo de confirmação. Um toque acidental fecha o turno. | ✅ |
| `popups/bloquear_tarefa_screen.dart:161` | Typo na validação: `'Por favor, detalhe o problem.'` | ✅ com (B)+(C)+(D) |

Transversal aos 6 ficheiros: `catch (e) { debugPrint(...) }` seguido de lista
vazia. Um erro de rede fica indistinguível de "não há trabalho para este posto".
`lib/widgets/estado_erro.dart` já existe e não é usado em lado nenhum.
✅ **Resolvido na secção 3**, como previsto: com `EstadoErro` ligado à camada de
repositório, e não com mais um `catch` local. Onde a falha silenciosa era
perigosa por si só, já tinha sido removida aqui (ver abaixo).

### Como foram resolvidos

**Cronómetro de produção — a única alteração à base de dados.** Migração
`add_data_inicio_fase_encomendas`:

- nova coluna `encomendas.data_inicio_fase` (`timestamptz`), com backfill a
  partir da última conclusão em `historico_producao` e, na falta dela, do
  `created_at` da ordem;
- `avancar_fase_encomenda` passa a escrever `data_inicio_fase = now()` na mesma
  transação da transição (e `null` quando a ordem fica concluída).

O ecrã lê a coluna em vez do `static Map`. O cronómetro deixa de zerar num
reinício da app e deixa de ser partilhado entre utilizadores do mesmo processo.
O tique do timer passou também a recalcular a partir do início real em vez de
somar 1 por segundo: com a app em segundo plano, o timer suspende e o valor
antigo ficava a marcar menos tempo do que o decorrido. Migração aditiva; o
painel do admin usa a mesma RPC e não precisou de alterações.

**Especificações técnicas falsas.** Não existe no schema coluna de dimensões
nem de material — não havia dado real a mostrar. O cartão passa a apresentar o
que a ordem tem mesmo: quantidade, prioridade, data de entrega, tempo estimado
da fase e observações (estas só quando preenchidas).

**Fallbacks a adivinhar colunas.** Confirmado contra o schema:
`encomendas.tipos_produtos_id` e `fases_padrao.tipos_produto_id`. Os nomes
alternativos não existem em coluna nenhuma. Ficou uma query por caso, sem
`try/catch` a engolir o resultado. A leitura de incidências perdeu igualmente o
`catch` silencioso: se falhasse, a ordem aparecia como desbloqueada e o operador
podia retomar trabalho numa ordem em hold.

**Progresso na fila.** Passa a usar a posição da fase na lista ordenada
(`indice / total`) em vez do valor da coluna `ordem`. O cálculo antigo assumia
numeração contígua desde 1; com uma fase removida do plano dava percentagens
erradas, incluindo acima de 100%.

**ID do operador.** `'EMP-2026-' + nome.hashCode` deu lugar a um identificador
derivado do `utilizador_id` da sessão (`OP-XXXXXXXX`), que é estável e não muda
quando o nome é corrigido. `_obterIniciais` passou a delegar em
`core/iniciais.dart`, a mesma implementação do admin — a cópia local dividia por
um espaço único e falhava com espaços repetidos.

**Fusos horários (não estava na lista, apareceu ao corrigir o resto).**
`data_conclusao` é `timestamptz` e chega em UTC. O histórico, os relatórios de
turno e o filtro por data comparavam-na com datas locais sem converter, o que
atribuía o trabalho de fim de turno ao dia seguinte. Todos os pontos passaram a
usar `toLocal()`, e o filtro do relatório de fecho de sessão envia `toUtc()`.

**Verificação:** `flutter analyze lib/screens/terminal_operador` — **0 issues**
(eram 8 no início da secção). `flutter analyze lib test` — 58 issues, todas
pré-existentes noutros módulos, nenhuma na pasta do operador.
`flutter test` — 146 testes, todos a passar.

### Achados novos, resolvidos na secção 3

- ✅ **Incidências deixaram de aparecer no histórico do operador.** Com (C), o
  ecrã já não cria o registo falso em `historico_producao`, e `aplicar_wip_hold`
  grava a incidência ligada à *encomenda*, sem `historico_producao_id`. Mas
  `historico_operador_screen` continuava a ir buscar as incidências pela relação
  `historico_producao_id`, que nunca mais é preenchida: a coluna de bloqueios
  ficou permanentemente vazia. Não era regressão de dados — era o ecrã a ler
  pela chave errada. Resolvido em `OperadorRepository.associarParagens` (ver
  secção 3).
- ✅ **`services/producao_service.dart`** mantinha uma segunda implementação do
  avanço de fase, com `insert` manual em `historico_producao` — a mesma classe
  de defeito que (A) corrigiu no terminal. Confirmado que nenhum ecrã nem teste
  o importava (era código morto desde o refactor do admin) e que todas as suas
  funções tinham equivalente vivo em `EncomendasRepository` e
  `FluxosRepository`. **Ficheiro eliminado**, para que ninguém volte a chamar o
  `insert` manual.

---

## 3. Dívida arquitetural face ao `dashboard_admin` — ✅ resolvida (2026-07-31)

| # | Ponto | Estado |
|:--|:---|:---|
| 1 | `Supabase.instance.client` direto nos 6 ficheiros | ✅ |
| 2 | Zero models — `Map<String, dynamic>` em todo o lado | ✅ |
| 3 | `EstadoOrdem` ignorado | ✅ |
| 4 | Duplicação com `lib/core/` (iniciais, formatos, mensagens, ~60 cores) | ✅ |
| 5 | Sem realtime nem pull-to-refresh na fila | ✅ |
| 6 | `IndexedStack` no shell não recarrega ao voltar | ✅ |
| 7 | Sem paginação no histórico | ✅ |
| 8 | Zero testes para o operador | ✅ |
| 9 | Depreciações (`withOpacity`, `DropdownButtonFormField.value`) | ✅ na secção 2 |
| — | `catch (e) { debugPrint }` seguido de lista vazia (transversal) | ✅ |

### Como foram resolvidos

**Camada de repositório — `lib/repositories/operador_repository.dart` (novo).**
Ficou separado do `EncomendasRepository` porque a audiência é outra: aqui tudo é
lido do ponto de vista de *um* operador e do *seu* posto. As transições de
estado continuam a ser as RPCs do `EncomendasRepository` — as mesmas que o admin
usa —, que é precisamente o que evita repetir o defeito de (A). Expõe
`obterPostoAtribuido`, `obterFila`, `obterDetalheTarefa`, `obterHistorico`,
`obterTurnos` e `obterResumoDaSessao`, e os tipos de retorno
`FilaDeTrabalho`, `OrdemNaFila`, `DetalheTarefa`, `RegistoDeTurno` e
`ResumoDeTurno`. Nenhum dos 6 ficheiros do terminal chama `Supabase.instance`
para dados de produção; sobra o `operador_shell_screen`, que usa o cliente
apenas para o `stream` do próprio perfil e para o `auth.updateUser` da
palavra-passe — nenhum dos dois é acesso a dados de negócio.

**Models.** Os ecrãs deixaram de manipular mapas. Acrescentou-se
`EncomendaModel.dataInicioFase` (a coluna que alimenta o cronómetro) e criou-se
`ReasonCodeModel`, que faltava — os motivos de paragem eram o último
`Map<String, dynamic>` a atravessar a interface, em dois ecrãs diferentes.
`EncomendasRepository.obterReasonCodes()` passa a devolver modelos **já
deduplicados por `id`**: a deduplicação estava escrita duas vezes, no painel de
controlo e no popup do operador, pelo mesmo motivo (o
`DropdownButtonFormField` lança em runtime com dois itens de igual valor).

`FaseModel.checklist` passou a normalizar as três formas em que a coluna `jsonb`
chega — lista de strings, lista de objetos `{"item": …}`, ou JSON ainda por
descodificar. O ecrã de detalhe fazia esse trabalho à mão e o caso do objeto
apresentava ao operador o texto `{item: Verificar solda}`.

**`EstadoOrdem`.** A fila e o detalhe derivam agora o estado por
`EstadoOrdem.derivar`. "Atrasado" e "Em Progresso" mantêm-se como leitura
operacional do cartão, mas só se aplicam a uma ordem em produção. O detalhe
ganhou um aviso explícito de WIP Hold com o motivo da paragem: antes limitava-se
a desativar os botões, sem dizer porquê.

**`lib/core/` partilhado.** Os literais `Color(0xFF…)` dos 6 ficheiros deram
lugar a `TemasCores`; os SnackBars montados à mão a `context.mostrarMensagem`;
`_formatarData` a `Formatos.dataHora`; `_obterIniciais` já delegava.

**Realtime e recarregamento.** A fila subscreve `encomendas` e `incidencias`
pelo canal que o painel de controlo já usava, com `RecarregadorDebounced` a
juntar as rajadas (avançar uma fase gera dois ou três eventos em poucos
milissegundos). Tem também pull-to-refresh e botão de recarregar. Uma ordem nova
no posto, ou um Line Clearance aprovado pelo admin, aparecem sem terminar
sessão.

**Separadores obsoletos.** O `IndexedStack` mantém-se — preserva scroll e
filtros —, mas o shell pede agora o recarregamento ao separador para onde se
entra, através da interface `EcraRecarregavel` (`core/ecra_recarregavel.dart`).
Só o separador de destino, e só quando é uma mudança real: tocar no separador já
ativo não dispara query nenhuma.

**Paginação do histórico.** 50 linhas de cada vez, com "Carregar mais". A
pesquisa, o filtro de data e a ordenação desceram para o servidor: com
paginação, aplicá-los em memória ordenaria e filtraria apenas a fatia já
carregada — a mesma armadilha que a pesquisa do painel de controlo teve. Há um
desempate por `id` para que duas linhas com a mesma data não troquem de posição
entre páginas.

Duas colunas deixaram de ser ordenáveis, por não serem ordenáveis no servidor:
**Produto** (o nome está a dois níveis de junção, `historico_producao →
encomendas → tipos_produto`, e o PostgREST só ordena pelo primeiro nível) e
**Estado** (vem de uma relação um-para-muitos). O estado passou a **filtro**
("Apenas bloqueados"), que é exato em qualquer caso. Ordenar por Produto
exigiria uma vista na base de dados; fica registado aqui e não foi feito, para
não misturar trabalho de schema com este passo.

**Erro visível.** Os `catch (e) { debugPrint(…) }` seguidos de lista vazia
desapareceram dos 6 ficheiros. `EstadoErro` — que existia e não era usado em
lado nenhum — cobre agora a fila, o histórico, os relatórios e o detalhe; no
histórico, a falha de uma página adicional usa `EstadoErro.compacto`, para não
apagar o que já está no ecrã.

**Testes.** 29 testes novos (`test/repositories/operador_repository_test.dart`,
`test/models/reason_code_model_test.dart`), sobre a lógica que se consegue
isolar: o cálculo de progresso no roteiro, a associação das paragens às fases e
o modelo dos reason codes. Total: **175 testes, todos a passar** (eram 146).

### Associação das paragens às fases (decisão)

A RPC `aplicar_wip_hold` grava a incidência contra a **encomenda**, sem
`historico_producao_id`. Ligar apenas pela encomenda marcaria como bloqueadas
todas as fases dessa ordem, incluindo as que correram sem problema. Optou-se por
ordem **+ janela de tempo**: a paragem pertence à primeira fase dessa encomenda
concluída **depois** do seu registo — a fase que estava a decorrer quando a
linha parou.

Consequência assumida: uma paragem numa fase ainda por concluir não aparece no
histórico. É coerente com o que o ecrã é — uma lista de fases concluídas — e
essa paragem está visível onde interessa, no cartão da ordem e no painel do
admin.

O mesmo cálculo alimenta os relatórios de turno e o relatório de fecho de
sessão, que contavam as incidências pela mesma FK morta e por isso davam zero.

**Verificação:** `flutter analyze lib/screens/terminal_operador lib/repositories
lib/models lib/core lib/widgets` — **0 issues** (a única que aparece é a
depreciação `anonKey` em `core/supabase_config.dart`, pré-existente e noutro
módulo). `flutter test` — **183 testes, todos a passar**.

---

## 3b. Revisão do código escrito na secção 3

O diagnóstico das secções 1 a 3 foi escrito **antes** das alterações. A secção 3
reescreveu 6 ficheiros e criou um repositório de raiz — código novo, que nenhum
diagnóstico tinha visto. Esta secção regista a releitura desse código e os 8
defeitos que ela encontrou, todos corrigidos.

| # | Onde | Defeito | Gravidade |
|:--|:---|:---|:---|
| 1 | `operador_repository` | Linha-sentinela da paginação não era descartada | Alta |
| 2 | `operador_shell` | Duplo `Navigator.pop` fechava o terminal | Alta |
| 3 | `operador_repository` | Paragens associadas só dentro da página | Média |
| 4 | `detalhe_tarefa` | Andon nunca avisava quando `tempo_estimado` era nulo | Média |
| 5 | `operador_repository` | `faseAtual` recuava para a primeira fase | Média |
| 6 | `fila_trabalho` | Falha transitória apagava a fila inteira | Média |
| 7 | `historico_operador` | "Apenas bloqueados" dava beco sem saída | Média |
| 8 | `historico_operador` | Barra de erro nunca desaparecia | Baixa |

**(1) Linha-sentinela repetida entre páginas.** A query pede `tamanho + 1`
linhas — a última é só a sonda que diz se há mais. O código construía a página
com **todas** as linhas devolvidas, incluindo a sonda. Resultado: o 51.º
registo aparecia no fim da primeira página e outra vez no início da segunda.
Passou a ser descartado antes de se construir a página.

**(2) Duplo `Navigator.pop` ao terminar sessão.** O diálogo de progresso era
fechado dentro do `try` e outra vez no `catch`. Se a geração do PDF falhasse — a
parte mais provável de falhar — o segundo `pop` desmontava o próprio terminal.
O mesmo bloco tinha um segundo defeito: o `if (!mounted) return` no `catch`
saltava o logout, deixando o operador com sessão aberta depois de a mandar
fechar. O diálogo passa a ser fechado uma única vez, e o `mounted` já só
condiciona a interface — sair é a parte que não pode falhar.

**(3) Paragens associadas apenas dentro da página.** A associação corria sobre
o histórico daquela fatia. Se a fase interrompida tivesse ficado na página
anterior, a paragem era atribuída à primeira fase visível desta — e a mesma
paragem mudava de linha conforme a paginação. Passou a resolver-se contra o
histórico completo das ordens envolvidas (`_associarParagensDasOrdens`), que
são no máximo 50 e custam uma query. O mesmo helper serve os relatórios de
turno e o fecho de sessão, que tinham o mesmo problema em menor escala.

Nota associada: esse histórico completo é lido **sem filtro de utilizador**, de
propósito. Uma ordem passa por vários postos e vários operadores, e a fase em
que a linha parou pode ter sido concluída por outra pessoa. Em contrapartida, o
`obterResumoDaSessao` conta agora explicitamente as fases **deste** operador
que tiveram paragem, e não as chaves todas do mapa.

**(4) Andon nunca avisava.** `FaseModel.tempoEstimado` é `0` quando a coluna vem
nula, e o ecrã fazia `tempoEstimado ?? 15` — que não dispara com zero. O rácio
contra zero nunca cresce, pelo que o cartão dizia "DENTRO DO PRAZO" para sempre
e anunciava "Estimado: 0 min". Regressão introduzida na secção 3: o código
antigo mantinha 15 como valor inicial e só o substituía se a coluna não fosse
nula. Agora o tempo estimado é `int?` e, sem estimativa, o cartão conta o tempo
mas não afirma prazo nenhum ("SEM TEMPO ESTIMADO").

**(5) `faseAtual` recuava para a primeira fase.** Quando a fase atual não
constava do roteiro carregado — roteiro alterado depois de a ordem ser lançada —
devolvia-se `fases.first`. Consequências: o cronómetro usava o tempo estimado da
fase errada, a timeline marcava "em andamento" um passo já ultrapassado, e a
confirmação de conclusão apresentava ao operador o nome de **outra** fase.
Passou a devolver `null`, com `faseForaDoRoteiro` a distinguir este caso do de
uma ordem concluída. O ecrã mostra um aviso "Fase atual não reconhecida" e não
deixa concluir: fechar a fase errada é pior do que ter de chamar a supervisão.

**(6) Falha transitória apagava a fila.** Com realtime, uma falha de rede é
frequente e esperada. O ecrã substituía a grelha inteira pelo `EstadoErro`,
fazendo desaparecer o trabalho que o operador estava a ver. Agora, com a fila já
carregada, a falha é uma barra `EstadoErro.compacto` por cima dos cartões; o
`EstadoErro` inteiro fica só para quando não há nada carregado.

**(7) Beco sem saída no filtro de bloqueios.** "Apenas bloqueados" é aplicado
depois de o servidor responder. Uma página de 50 fases sem paragem nenhuma dava
lista vazia, e o ecrã respondia "não há registos" sem oferecer o botão de
carregar mais — com páginas por percorrer. O botão passa a aparecer sempre que
haja mais para ler, com um texto que distingue "não há nada" de "não há nada
**até aqui**".

**(8) Barra de erro permanente.** O `_erro` do histórico não era limpo depois de
um "Repetir" bem-sucedido: a barra ficava no ecrã para sempre.

### Alteração de comportamento decidida na revisão

**Checklist e confirmação deixaram de se somar.** Numa fase com checklist, o
operador marcava os pontos de controlo um a um, carregava em "Validar & Concluir
Fase" — e apanhava logo a seguir um "Tem a certeza?". Encadear os dois diálogos
só ensina a despachá-los sem ler, que é exatamente o que a confirmação existe
para evitar. A confirmação passou a servir apenas as fases **sem** checklist,
onde de outro modo bastaria um toque para fechar a fase.

### O que a revisão não cobre

Nenhum destes 8 defeitos teria sido apanhado pelos testes automáticos, e a
revisão também não substitui a validação manual: continua por confirmar contra a
app real que a sintaxe PostgREST do histórico está correta — o filtro
`encomendas.codigo_rastreio` com `!inner` e o `order(referencedTable:)`. São a
única parte do módulo cuja correção não se consegue demonstrar sem servidor.

**Verificação:** `flutter analyze lib/screens/terminal_operador` — **0 issues**.
`flutter test` — **183 testes** (mais 8 sobre `DetalheTarefa.faseAtual` e
`DetalheTarefa.bloqueada`, o comportamento alterado nos pontos 5 e 6).

---

## 4. Para elevar o módulo a terminal de fábrica

- ⏳ **Autorização a sério.** `DetalheTarefaScreen(encomendaId:)` abre qualquer
  ordem por ID; a única barreira é a fila não mostrar o cartão. **Confirmado por
  query (2026-07-31):** `relrowsecurity = false` em todas as tabelas do módulo e
  privilégios `arwdDxtm` concedidos a `anon` — não é só o ecrã que não filtra, é
  a base de dados que não impõe nada. **Adiado por decisão para último passo:**
  nenhuma tabela do projeto tem RLS ativa, pelo que ativá-la é trabalho
  transversal a toda a aplicação, não deste módulo.
- **Ergonomia com luvas.** Botões de 38-40 px e tipografia de 11-13 px são
  pequenos de mais para toque industrial; `padding: 40` fixo desperdiça ecrã em
  tablet. Alvos ≥56 px, tipografia escalável, modo de alto contraste.
- **Leitura de código de barras / QR** para abrir a ordem — praticamente
  obrigatório no domínio e elimina o erro de abrir o cartão errado.
- **Resiliência offline.** O Wi-Fi de fábrica cai; hoje a ação perde-se com um
  SnackBar vermelho. Fila de escrita local com reenvio.
- 🟡 **Confirmação e undo** ao concluir fase. **Confirmação feita** na secção 3:
  concluir a fase pede confirmação com o nome da fase e da ordem, a seguir à
  checklist quando a fase a define. O **undo continua por fazer** — recuar uma
  fase exige uma RPC nova (o inverso de `avancar_fase_encomenda`, a apagar o
  registo de histórico e a repor `data_inicio_fase`), o que é trabalho de
  servidor e não de ecrã.
- **Acessibilidade.** Estado comunicado apenas por cor, sem `Semantics` nem
  tooltips.

---

## Ordem de execução

1. ✅ **(A) + (B) + (C)** — `_concluirFase` e o popup de incidência passaram
   para as RPCs `avancar_fase_encomenda` e `aplicar_wip_hold`. Resolveu
   transacionalidade, bloqueio real e corrupção do histórico de uma vez.
2. ✅ **(D) + (E)** — `reason_codes` no popup e filtro de estado na fila via
   `EstadoOrdem`.
3. ✅ **Secção 2** — os 13 bugs de segundo nível.
4. ✅ **Camada de repositório + models** nos 6 ecrãs, seguindo o guião dos
   passos 1-2 do `ARQUITETURA_REFACTOR.md`.
5. ✅ **Realtime, tratamento de erro visível, `lib/core/` partilhado,
   paginação e testes.**
6. ⏳ **Validação manual** do checklist de 7 passos da secção 1, contra a app
   real. Nada disso foi ainda corrido.
7. ⏳ **Ergonomia de terminal** (alvos ≥56 px, tipografia escalável),
   **leitura de QR**, **resiliência offline**, **undo** e **acessibilidade** —
   secção 4.
8. ⏳ **RLS e privilégios**, por decisão o último passo: hoje `anon` escreve
   diretamente em `encomendas`, `historico_producao` e `incidencias`, sem passar
   pelas RPCs onde vivem as regras de negócio. É trabalho transversal a toda a
   aplicação.
