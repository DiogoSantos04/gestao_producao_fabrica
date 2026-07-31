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
| Secções 3 e 4 | pendentes — **próximo** |

Secção 1 fechada e verificada contra a base de dados: permissões das RPCs
confirmadas e zero registos corrompidos por (C) — detalhes abaixo. Fica em
aberto um achado de segurança novo (RLS desligada, `anon` com escrita total),
registado em (B)/(C) e na secção 4.

## Contexto

6 ficheiros, ~2.100 linhas:

| Ficheiro | Linhas aprox. |
|:---|---:|
| `detalhe_tarefa_screen.dart` | 807 |
| `historico_operador_screen.dart` | 546 |
| `operador_shell_screen.dart` | 622 |
| `fila_trabalho_screen.dart` | 390 |
| `relatorios_operador_screen.dart` | 273 |
| `popups/bloquear_tarefa_screen.dart` | 214 |

Conclusão geral: **a pasta ficou congelada no estado pré-refactor**. Nenhum dos
6 ficheiros usa `lib/repositories/`, `lib/models/`, `lib/core/` ou
`lib/widgets/`. Agrava-se por conterem as duas escritas mais críticas de toda a
aplicação — avançar de fase e bloquear produção — e ambas estarem erradas.

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
**Continua por resolver** — é trabalho da secção 3, porque a solução é o
`EstadoErro` ligado à camada de repositório, não mais um `catch` local. Onde a
falha silenciosa era perigosa por si só, foi removida já (ver abaixo).

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

### Achados novos, para a secção 3

- **Incidências deixaram de aparecer no histórico do operador.** Com (C), o
  ecrã já não cria o registo falso em `historico_producao`, e `aplicar_wip_hold`
  grava a incidência ligada à *encomenda*, sem `historico_producao_id`. Mas
  `historico_operador_screen` continua a ir buscar as incidências pela relação
  `historico_producao_id`, que agora nunca é preenchida: a coluna de bloqueios
  ficou permanentemente vazia. Não é regressão de dados — é o ecrã a ler pela
  chave errada. A correção é passar a ler por `encomenda_id`, e faz-se junto com
  a migração deste ecrã para repositório e models.
- **`services/producao_service.dart` mantém uma segunda implementação do avanço
  de fase**, com `insert` manual em `historico_producao`
  (`novoHistoricoId` está inclusive marcado como variável não usada pelo
  analisador). É a mesma classe de defeito que (A) corrigiu no terminal. Falta
  confirmar quem ainda a chama e eliminá-la em favor da RPC.

---

## 3. Dívida arquitetural face ao `dashboard_admin`

1. **`Supabase.instance.client` direto nos 6 ficheiros.** Falta usar
   `postos_repository` (já existe) e acrescentar os métodos de operador a
   `encomendas_repository`, ou criar um `operador_repository.dart`.
2. **Zero models.** `Map<String, dynamic>` e `List<dynamic>` em todo o lado —
   o mesmo risco de `NoSuchMethodError` invisível ao `flutter analyze` descrito
   no passo 2 do refactor. `EncomendaModel`, `HistoricoModel`, `IncidenciaModel`
   e `FaseModel` já cobrem estes ecrãs.
3. **`EstadoOrdem` ignorado.** A fila define o seu próprio par estado/cor
   ("Pronto a Iniciar" / "Em Progresso" / "Atrasado"), que não coincide com
   nenhuma etiqueta do admin: operador e supervisor veem palavras diferentes
   para a mesma ordem.
4. **Duplicação com `lib/core/`:** `_obterIniciais` (existe `core/iniciais.dart`),
   `_formatarData` e `_formatarTempo` (`core/formatos.dart`), SnackBars montados
   à mão (`core/mensagens.dart`), cerca de 60 literais `Color(0xFF...)`
   (`core/temas_cores.dart`).
5. **Sem realtime.** O ecrã operacionalmente mais crítico é o único estático da
   aplicação. Uma ordem nova no posto, ou um line clearance aprovado pelo admin,
   só aparecem se o operador terminar sessão. `RecarregadorDebounced`
   (`core/realtime.dart`) já está construído. Não há sequer pull-to-refresh nem
   botão de recarregar.
6. **`IndexedStack` no shell** mantém os 4 separadores vivos e nenhum recarrega
   ao voltar — dados obsoletos por tempo indefinido.
7. **Sem paginação** no histórico (`core/paginacao.dart` existe): carrega tudo e
   filtra/ordena em memória.
8. **Zero testes** para o operador. Os 9 testes existentes cobrem apenas models e
   `estado_erro`.
9. ~~**Depreciações pendentes:** `withOpacity` e
   `DropdownButtonFormField.value`.~~ ✅ Resolvidas nesta pasta com a secção 2
   (`withValues` / `initialValue`). Continuam presentes noutros módulos.

---

## 4. Para elevar o módulo a terminal de fábrica

- **Autorização a sério.** `DetalheTarefaScreen(encomendaId:)` abre qualquer
  ordem por ID; a única barreira é a fila não mostrar o cartão. **Confirmado por
  query (2026-07-31):** `relrowsecurity = false` em todas as tabelas do módulo e
  privilégios `arwdDxtm` concedidos a `anon` — não é só o ecrã que não filtra, é
  a base de dados que não impõe nada. Passou a ser o ponto mais importante que
  resta, agora que (A)–(E) e a secção 2 estão fechadas.
- **Ergonomia com luvas.** Botões de 38-40 px e tipografia de 11-13 px são
  pequenos de mais para toque industrial; `padding: 40` fixo desperdiça ecrã em
  tablet. Alvos ≥56 px, tipografia escalável, modo de alto contraste.
- **Leitura de código de barras / QR** para abrir a ordem — praticamente
  obrigatório no domínio e elimina o erro de abrir o cartão errado.
- **Resiliência offline.** O Wi-Fi de fábrica cai; hoje a ação perde-se com um
  SnackBar vermelho. Fila de escrita local com reenvio.
- **Confirmação e undo** ao concluir fase (hoje só há checklist quando a fase a
  define).
- **Acessibilidade.** Estado comunicado apenas por cor, sem `Semantics` nem
  tooltips.

---

## Ordem de execução sugerida

1. **(A) + (B) + (C)** — passar `_concluirFase` e o popup de incidência para as
   RPCs `avancar_fase_encomenda` e `aplicar_wip_hold`. Resolve
   transacionalidade, bloqueio real e corrupção do histórico de uma vez. É onde
   os dados estão a ser efetivamente corrompidos.
2. **(D) + (E)** — `reason_codes` no popup e filtro de estado na fila via
   `EstadoOrdem`.
2b. **Secção 2** — ✅ feita. Ver "Como foram resolvidos" acima.
3. **RLS e privilégios** (ver o aviso de segurança na secção 1): hoje `anon`
   escreve diretamente em `encomendas`, `historico_producao` e `incidencias`,
   sem passar pelas RPCs onde vivem as regras de negócio.
4. **Camada de repositório + models** nos 6 ecrãs, seguindo o guião dos passos
   1-2 do `ARQUITETURA_REFACTOR.md` — incluindo a mitigação de tipar as
   declarações de campo **antes** de converter os acessos por mapa.
4. **Realtime, tratamento de erro visível e `lib/core/` partilhado.**
5. **Ergonomia de terminal e testes.**
