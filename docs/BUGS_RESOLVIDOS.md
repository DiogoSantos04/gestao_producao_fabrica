# Correção de Bugs — Módulo `dashboard_admin`

> Sessão de correção focada exclusivamente em bugs. Sem refactor de arquitetura,
> sem novas funcionalidades. Data: 2026-07-24.

---

## 1. Contexto

O ponto de partida foi uma revisão completa dos 10 ficheiros de
`lib/screens/dashboard_admin/` (~9.100 linhas). A revisão identificou problemas em
três frentes — segurança, integridade de dados e arquitetura — das quais **só a
correção de bugs foi executada nesta sessão**.

Foram identificados **7 bugs**, categorizados por gravidade e etiquetados de (a) a (g):

| Ref. | Gravidade | Bug | Estado |
|:---:|:---|:---|:---:|
| **a** | Crítica | Funcionalidade totalmente inoperante: estados dos postos e ligação fase↔posto | ✅ |
| **b** | Crítica | KPI errado num documento auditado (taxa de entrega no prazo) | ✅ |
| **c** | Crítica | Passwords em texto simples numa tabela publicamente legível | ✅ |
| **d** | Alta | Operações multi-passo sem atomicidade | ✅ |
| **e** | Alta | `DELETE` físico de ordens de produção destruía a rastreabilidade | ✅ |
| **f** | Média | Notificações endereçadas por comparação de strings | ✅ |
| **g** | Baixa | Conjunto de bugs menores (desempenho, typo, valores fixos, dessincronização) | ✅ |

Durante a execução apareceu **1 bug adicional** não previsto na lista inicial
(incidências resolvidas contabilizadas como paragens ativas), também corrigido.

**Total: 8 bugs corrigidos.**

---

## 2. Bugs resolvidos

### (a) — CRÍTICA — Ecrã de Postos de Trabalho inoperante

**Problema.** Duas falhas independentes no mesmo ecrã:
1. Atribuir um operador ou marcar manutenção não produzia efeito algum.
2. Nenhum posto mostrava a ordem em curso; os KPIs do topo indicavam sempre
   "Disponíveis" para todos os postos.

**Causa raiz.**
1. O código Dart escrevia `'LIVRE'`, `'OCUPADO'`, `'MANUTENCAO'` na coluna
   `postos_trabalho.estado`, mas a base de dados tem um `CHECK` que só aceita
   `'Livre'`, `'Em Produção'`, `'Parado'`. **Todos os `UPDATE` falhavam** com violação
   de constraint. O erro era apanhado por um `catch` que mostrava um snackbar
   genérico, pelo que a falha passava por problema de rede.
2. A associação entre ordem e posto era feita comparando **texto livre**:
   `postos_trabalho.nome_posto` contra `fases_padrao.posto_trabalho`. Só que este
   segundo campo era preenchido a partir de uma **lista hardcoded em Dart**
   (`_postosTrabalhoDisponiveis`, com valores como `'Posto de Lixagem'`) que não
   correspondia aos registos reais da tabela (`'Corte'`, `'Montagem'`, …).

   Levantamento dos dados em produção confirmou a divergência: de 30 fases, 24 casavam
   por coincidência e 6 nunca casariam (`Posto de Lixagem`, `Posto de Controlo de
   Qualidade`, `Posto de Pintura / Lacagem`, `Posto de Secagem`, `Posto de Embalamento`,
   e uma legada `Serra de bancada`).

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/postos_trabalho_screen.dart`
- Migração: `fases_padrao_fk_posto_trabalho`

**Alterações ao schema.**
- **Novos registos:** criados os postos `Lixagem` e `Controlo de Qualidade`, que
  existiam apenas como texto nas fases.
- **Nova coluna:** `fases_padrao.posto_trabalho_id INTEGER REFERENCES postos_trabalho(id)`.
- **Backfill:** todas as 30 fases ligadas, com tabela explícita de *aliases* para
  os valores do catálogo hardcoded e do legado. Resultado verificado: **0 fases órfãs**.
- **Novo índice:** `idx_fases_padrao_posto`.
- **Novo trigger:** `trg_sync_fase_posto_texto` (+ função `sync_fase_posto_texto`),
  que mantém a coluna de texto legada sincronizada a partir da FK.

**Justificação técnica.**
- *Para os estados:* havia duas opções — alinhar o Dart com o `CHECK`, ou migrar o
  `CHECK` para os valores do Dart. Escolhi alinhar o Dart porque os valores da BD são
  os que estão efetivamente gravados nas 5 linhas existentes e são os que aparecem
  na UI; migrar o `CHECK` obrigaria a reescrever dados e a validar todos os outros
  consumidores. Os valores passaram a viver numa classe `EstadoPosto`, para que a
  próxima divergência seja um erro de compilação e não uma falha silenciosa em runtime.
- *Para `'OCUPADO'`:* não tem correspondência no `CHECK` e não precisa de existir —
  é derivável de `operador_id != null`. Passou a ser calculado na UI em vez de persistido,
  eliminando um estado redundante.
- *Para a ligação:* uma FK é a única forma de tornar a relação verificável pela BD.
  A alternativa (normalizar as strings em Dart) manteria a possibilidade de divergirem.
- *Porque mantive a coluna de texto:* o terminal do operador
  (`fila_trabalho_screen.dart:57`) ainda filtra por ela e está fora do âmbito destes
  bugs. O trigger garante que não pode divergir da FK, pelo que a duplicação é segura
  e temporária.

---

### (b) — CRÍTICA — Taxa de entrega no prazo incorreta em relatório auditado

**Problema.** O total de ordens concluídas e a taxa de entrega no prazo estavam
inflacionados. Estes valores são impressos no PDF com carimbo de auditoria e
gravados em `historico_relatorios`.

**Causa raiz.** Em `relatorios_admin_screen.dart` havia esta regra:

```dart
if (!estaConcluida && faseAtualId == idUltimaFase && idUltimaFase != null) {
  estaConcluida = true;
  ...
  dataConclusaoReal = DateTime.now();   // ← data inventada
}
```

Estar **na** última fase foi tratado como ter **terminado** a última fase. Uma ordem
ainda em execução no posto final era contada como concluída, e na ausência de histórico
usava-se `DateTime.now()` como data de conclusão — o que a fazia parecer sempre no prazo.
Isto contradizia a definição usada no resto da aplicação (`fase_atual_id == null`).

Bug secundário na mesma função: `fase['types_produto_id'] ?? fase['tipos_produto_id']`
— chave inexistente por typo, que só não rebentava por causa do operador `??`.

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/relatorios_admin_screen.dart`

**Alterações ao schema.** Nenhuma.

**Justificação técnica.** Em vez de corrigir a condição nos dois sítios onde estava
duplicada (cálculo global e geração do PDF), extraí a regra para dois helpers —
`_obterDataConclusao()` e `_cumpriuPrazo()` — usados por ambos. A causa raiz aqui não
foi só a condição errada: foi a lógica de negócio estar reimplementada em dois lugares,
com liberdade para divergir. A data de conclusão passou a ser o `max(data_conclusao)`
do histórico real, nunca um valor sintético. Acrescentei também `.eq('cancelada', false)`
para que ordens canceladas não entrem em indicadores de desempenho.

---

### (c) — CRÍTICA — Palavras-passe guardadas em texto simples

**Problema.** As palavras-passe dos utilizadores eram gravadas em claro na coluna
`utilizadores.password`, em paralelo com o Supabase Auth.

**Causa raiz.** Os diálogos de alteração de palavra-passe faziam duas escritas: uma no
Auth (correto, encriptada) e outra na tabela pública (em claro), com o comentário
`// 2. Sincroniza a coluna 'password'`. Como o RLS está desativado nesta tabela,
qualquer pessoa com a chave `anon` — que está embutida no bundle da app web —
conseguia ler as palavras-passe de todas as contas.

O padrão estava replicado em **três** ecrãs, não apenas no módulo admin.

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/dashboard_admin_shell.dart`
- `lib/screens/portal_cliente/cliente_shell_screen.dart`
- `lib/screens/terminal_operador/operador_shell_screen.dart`
- Migração: `drop_utilizadores_password_texto_simples`

**Alterações ao schema.**
- **Coluna removida:** `utilizadores.password` (`DROP COLUMN`).

**Justificação técnica.** Remover só o código deixaria os valores já gravados expostos,
pelo que a coluna tinha de desaparecer. Confirmei por `grep` que nenhum ficheiro do
projeto escrevia ou lia `'password'` na tabela antes de aplicar o `DROP` — o `DROP`
foi o último passo, não o primeiro. O Auth é a única fonte de verdade para credenciais;
uma coluna paralela não tem caso de uso legítimo, portanto não havia razão para a
substituir por um hash.

> **Nota:** o RLS continua desativado em 12 tabelas. Está fora do âmbito desta sessão
> e é o problema de segurança que resta.

---

### (d) — ALTA — Operações multi-passo sem atomicidade

**Problema.** Sequências de escritas relacionadas podiam falhar a meio, deixando dados
inconsistentes sem qualquer indicação.

**Causa raiz.** Quatro fluxos críticos faziam 2 a 4 chamadas independentes ao Supabase:

| Fluxo | Escritas | Consequência de falha intermédia |
|:---|:---|:---|
| Avançar fase | `INSERT` histórico → `UPDATE` encomenda | Histórico órfão; ordem presa na fase anterior |
| WIP Hold | `INSERT` incidência → `UPDATE em_suspenso` | Incidência aberta sem a ordem suspensa |
| Line Clearance | `UPDATE` incidência → `UPDATE` encomenda | Incidência fechada com a ordem presa em hold |
| Aprovar pedido | 4 escritas | Ordem lançada com o pedido ainda "Pendente" |

Além disso, as regras de negócio (não avançar uma ordem em hold, não aplicar dois holds
seguidos, não validar clearance sem manutenção registada) não eram validadas em lado nenhum.

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/painel_controlo_screen.dart`
- `lib/screens/dashboard_admin/pedidos_clientes_admin_screen.dart`
- Migração: `rpcs_atomicas_producao`

**Alterações ao schema — 5 novas funções RPC:**

| Função | Responsabilidade | Guardas de negócio |
|:---|:---|:---|
| `avancar_fase_encomenda(bigint)` | Histórico + transição de fase | Rejeita ordem cancelada, em hold, ou já concluída |
| `aplicar_wip_hold(bigint, integer, text)` | Incidência + suspensão | Rejeita hold duplicado; valida o reason code |
| `aprovar_line_clearance(bigint)` | Fecha incidência + liberta ordem | Exige manutenção previamente registada |
| `aprovar_pedido_encomenda(bigint, date, text)` | Ordem + estado do pedido + notificação | Rejeita pedido já processado; exige fases definidas |
| `cancelar_ordem(bigint, text)` | Cancelamento + fecho de incidências | Exige motivo não vazio |

**Justificação técnica.** As RPCs correm em `SECURITY INVOKER` — mantêm as permissões
do utilizador autenticado, pelo que não abrem um bypass ao RLS quando este for ativado.
Usam `SELECT ... FOR UPDATE` para bloquear a linha e evitar corridas entre dois
administradores a operar a mesma ordem.

Mover as regras para a BD, e não deixá-las validadas em Dart, foi deliberado: há três
clientes distintos (admin, terminal do operador, portal do cliente) e uma regra validada
apenas na UI é uma regra que qualquer chamada direta à API contorna. O servidor passou a
ser o guardião. As funções lançam mensagens de negócio legíveis em português, mostradas
ao utilizador através do helper `_limparErro()`.

Também deixou de ser necessário resolver o posto de trabalho em Dart no WIP Hold —
a RPC deriva-o da fase atual, o que corrige de passagem o `posto_trabalho_id` das
incidências, que antes ficava sempre nulo.

---

### (e) — ALTA — `DELETE` físico destruía a rastreabilidade

**Problema.** Cancelar uma ordem apagava-a definitivamente da base de dados.

**Causa raiz.** `_cancelarOrdem()` executava
`await _supabase.from('encomendas').delete().eq('id', id)`, com o diálogo a confirmar
literalmente *"cancelar e apagar a ordem do sistema"*. O histórico de produção e as
incidências associadas ficavam órfãos ou eram removidos em cascata. Num contexto fabril,
uma ordem de produção não se apaga — perde-se o rasto de auditoria.

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/painel_controlo_screen.dart`
- `lib/screens/dashboard_admin/dashboard_principal_screen.dart`
- `lib/screens/dashboard_admin/relatorios_admin_screen.dart`
- `lib/screens/dashboard_admin/criar_encomenda_screen.dart`
- `lib/screens/dashboard_admin/postos_trabalho_screen.dart`
- Migrações: `soft_cancel_encomendas_e_link_cliente_utilizador`, `rpcs_atomicas_producao`

**Alterações ao schema.**
- **Novas colunas em `encomendas`:**
  - `cancelada BOOLEAN NOT NULL DEFAULT false`
  - `motivo_cancelamento TEXT`
  - `cancelada_por UUID REFERENCES utilizadores(utilizador_id)`
  - `data_cancelamento TIMESTAMPTZ`
- **Novo índice parcial:** `idx_encomendas_cancelada` sobre `cancelada = false`
  (o caso consultado em quase todos os ecrãs).

**Justificação técnica.** Considerei adicionar uma coluna `estado` com
`('EM_PRODUCAO','CONCLUIDA','CANCELADA')`, mas rejeitei: "concluída" já é representado
por `fase_atual_id IS NULL` e introduzir uma segunda fonte de verdade para o mesmo facto
criaria exatamente o tipo de divergência que o bug (b) demonstrou. Um booleano `cancelada`
é **ortogonal** ao progresso no roteiro, não o duplica.

O motivo passou a ser obrigatório e validado nos dois lados (botão desativado na UI,
`RAISE EXCEPTION` na RPC) — um cancelamento sem justificação não tem valor de auditoria.
Os cinco ecrãs que agregam encomendas passaram a filtrar `cancelada = false`, e o painel
ganhou um filtro dedicado "Canceladas" com um banner que mostra motivo, autor e data.

---

### (f) — MÉDIA — Notificações endereçadas por comparação de strings

**Problema.** Ao aprovar um pedido, a notificação de "Encomenda Aprovada" podia não
chegar ao cliente, ou chegar ao cliente errado.

**Causa raiz.** Não existia ligação entre `clientes` e `utilizadores`. O código procurava
a conta assim:

```dart
.eq('nome_utilizador', nomeCliente)   // clientes.nome_cliente == utilizadores.nome_utilizador
```

Um espaço a mais, uma diferença de acentuação ou dois utilizadores homónimos, e a
notificação desaparecia em silêncio ou ia para a pessoa errada.

**Ficheiros alterados.**
- `lib/screens/dashboard_admin/pedidos_clientes_admin_screen.dart`
- Migrações: `soft_cancel_encomendas_e_link_cliente_utilizador`,
  `auto_ligar_cliente_a_utilizador_por_email`

**Alterações ao schema.**
- **Nova coluna:** `clientes.utilizador_id UUID REFERENCES utilizadores(utilizador_id)`.
- **Novo índice único parcial:** `uq_clientes_utilizador` (uma conta não pode servir
  dois clientes).
- **Backfill:** por email (normalizado); em segunda passagem por nome exato, mas
  **apenas** quando não há ambiguidade — a subquery exige `count(*) = 1`.
- **Dois novos triggers bidirecionais:**
  - `trg_ligar_cliente_utilizador` — ao criar/alterar um cliente, liga pelo email.
  - `trg_ligar_utilizador_cliente` — ao criar/alterar um utilizador, liga a ficha de
    cliente existente.

**Justificação técnica.** Trocar a comparação de nome por comparação de email seria uma
melhoria, mas continuaria a ser um *match* por string. A FK resolve a causa e não o sintoma.

Os triggers bidirecionais existem porque as duas entidades podem ser criadas em qualquer
ordem — o admin pode registar a ficha do cliente antes de este criar conta, ou vice-versa.
Sem eles, a ligação só existiria para os registos abrangidos pelo backfill e o bug voltaria
para todos os clientes novos. Deste modo não foi preciso alterar a UI de criação de clientes,
o que manteria a correção dentro do âmbito de "bug", sem virar funcionalidade nova.

---

### (g) — BAIXA — Bugs menores

Todos corrigidos.

| Bug | Causa raiz | Correção | Ficheiro |
|:---|:---|:---|:---|
| Dashboard reconstruía-se 60×/min | `Timer.periodic(1s)` com `setState()` global, só para refrescar textos "há X min" | Passou a 30s e só dispara se existirem alertas | `dashboard_principal_screen.dart` |
| Typo visível na UI | "Distribuição por Fase de **Production**" | Corrigido para "Produção" | `dashboard_principal_screen.dart` |
| Ano fixo em referências | `'ORD-2026-'` copiado em 4 ficheiros | Novo `Formatos.referenciaOrdem()`, ano derivado de `created_at` | `lib/core/formatos.dart` (novo) + 3 ecrãs |
| ID do admin instável | Derivado de `_nomeUtilizador.hashCode` — mudava ao mudar o nome | Derivado do UUID real da conta Auth | `dashboard_admin_shell.dart` |
| Email dessincronizado do Auth | O admin editava `utilizadores.email` mas não o Auth; o utilizador deixava de conseguir entrar com o email que via | Campo passou a *read-only*; `_atualizarUtilizador()` já não recebe nem escreve o email | `gestao_utilizadores_screen.dart` |

---

### (h) — BÓNUS — Incidências resolvidas contadas como paragens ativas

Não constava da lista inicial; apareceu ao trabalhar no dashboard.

**Problema.** O painel "Alertas de Incidência" mostrava incidências já encerradas, e a
"Disponibilidade de Postos" ficava permanentemente abaixo de 100%.

**Causa raiz.** A query carregava **todas** as linhas de `incidencias`, sem filtrar por
estado. Como o cálculo de disponibilidade marca como bloqueado todo o posto com
incidência, uma paragem resolvida em janeiro continuaria a descontar indefinidamente.

**Correção.** `.eq('line_clearance_validado', false)` na query.
**Ficheiro.** `dashboard_principal_screen.dart`. **Schema.** Sem alterações.

---

## 3. Alterações estruturais à base de dados

Cinco migrações aplicadas ao projeto `hnilivakkwvnvgyblmss`, por ordem cronológica:

### 1. `fases_padrao_fk_posto_trabalho`
- `INSERT` dos postos `Lixagem` e `Controlo de Qualidade`
- `ADD COLUMN fases_padrao.posto_trabalho_id INTEGER REFERENCES postos_trabalho(id)`
- Backfill com tabela de *aliases* (30/30 fases ligadas, 0 órfãs)
- `CREATE FUNCTION sync_fase_posto_texto()` + `TRIGGER trg_sync_fase_posto_texto`
- `CREATE INDEX idx_fases_padrao_posto`

### 2. `soft_cancel_encomendas_e_link_cliente_utilizador`
- `ADD COLUMN encomendas.cancelada BOOLEAN NOT NULL DEFAULT false`
- `ADD COLUMN encomendas.motivo_cancelamento TEXT`
- `ADD COLUMN encomendas.cancelada_por UUID → utilizadores(utilizador_id)`
- `ADD COLUMN encomendas.data_cancelamento TIMESTAMPTZ`
- `CREATE INDEX idx_encomendas_cancelada` (parcial, `WHERE cancelada = false`)
- `ADD COLUMN clientes.utilizador_id UUID → utilizadores(utilizador_id)`
- Backfill por email e, sem ambiguidade, por nome
- `CREATE UNIQUE INDEX uq_clientes_utilizador` (parcial)

### 3. `rpcs_atomicas_producao`
- `CREATE FUNCTION avancar_fase_encomenda(bigint) RETURNS jsonb`
- `CREATE FUNCTION aplicar_wip_hold(bigint, integer, text) RETURNS bigint`
- `CREATE FUNCTION aprovar_line_clearance(bigint) RETURNS void`
- `CREATE FUNCTION aprovar_pedido_encomenda(bigint, date, text) RETURNS bigint`
- `CREATE FUNCTION cancelar_ordem(bigint, text) RETURNS void`

### 4. `drop_utilizadores_password_texto_simples`
- `ALTER TABLE utilizadores DROP COLUMN password`

### 5. `auto_ligar_cliente_a_utilizador_por_email`
- `CREATE FUNCTION ligar_cliente_utilizador()` + `TRIGGER trg_ligar_cliente_utilizador`
- `CREATE FUNCTION ligar_utilizador_cliente()` + `TRIGGER trg_ligar_utilizador_cliente`

**Resumo:** 6 colunas adicionadas, 1 removida, 3 novas FKs, 5 novas RPCs,
4 novas funções de trigger com 4 triggers, 3 novos índices.

---

## 4. Verificação e qualidade

### `flutter analyze`

| Momento | Erros | Avisos |
|:---|:---:|:---:|
| Antes das alterações (via `git stash`) | 0 | 8 |
| Depois das alterações | **0** | **8** |

**Nenhum aviso novo foi introduzido.** A comparação foi feita empiricamente: guardei as
alterações com `git stash`, corri o analisador na árvore original, e restaurei — não me
limitei a assumir que os avisos eram pré-existentes.

Os 8 avisos que subsistem já existiam e são todos alheios a estas correções:
imports por usar em `dashboard_principal_screen.dart`, `relatorios_admin_screen.dart`,
`operador_shell_screen.dart` e `pdf_service.dart`; verificação de tipo redundante em
`detalhe_tarefa_screen.dart`; duas comparações a `null` desnecessárias em
`auth_service.dart`; uma variável local não utilizada em `producao_service.dart`.

### Teste das RPCs contra a base de dados real

As 5 funções foram executadas num bloco `DO` sobre dados reais, terminado com
`RAISE EXCEPTION 'ROLLBACK_INTENCIONAL'` para reverter tudo. O bloco continha asserções
que rebentariam com uma mensagem distinta em caso de falha; como o erro devolvido foi
exatamente `ROLLBACK_INTENCIONAL`, a execução chegou ao fim e **todas as asserções passaram**:

Caminhos felizes verificados:
- `avancar_fase_encomenda` — transita e devolve a fase seguinte
- `aplicar_wip_hold` — cria a incidência e suspende
- `aprovar_line_clearance` — fecha e liberta, após manutenção registada
- `cancelar_ordem` — cancela com motivo

Guardas de negócio verificadas (todas rejeitaram como esperado):
- Line Clearance **sem** manutenção registada
- Cancelamento **sem** motivo (string só com espaços)
- Avanço de fase numa ordem **cancelada**

Após o rollback, confirmei por query que o estado ficou intacto:
`encomendas_canceladas = 0`, `incidencias_teste = 0`, `registos_historico = 3`
(inalterado), `fases_sem_posto = 0`, `clientes_ligados = 1`, `coluna_password = 0`.

### Testes manuais recomendados (não executados)

A aplicação não foi lançada nesta sessão. Recomendo validar na UI:
1. **Postos de Trabalho** — atribuir operador e alternar manutenção (o fluxo que estava
   totalmente inoperante).
2. **Painel de Controlo** — cancelar uma ordem e confirmar que aparece no filtro
   "Canceladas" com o banner de motivo, e que o histórico se mantém acessível.
3. **Pedidos de Clientes** — aprovar um pedido e confirmar que a notificação chega.
4. **Relatórios** — gerar um PDF e comparar o total de concluídas com o painel.

---

## 5. Trabalho pendente

Os itens (a) a (h) e a verificação final estão **todos concluídos**. O que segue ficou
de fora por decisão deliberada, não por estar a meio:

| Item | Porque ficou de fora |
|:---|:---|
| **RLS desativado em 12 tabelas** | Não constava da lista a–g. É o problema de segurança mais grave que resta: com a chave `anon`, um cliente autenticado pode alterar qualquer registo. Exige desenhar policies por perfil. |
| **Remover `fases_padrao.posto_trabalho` (texto)** | O terminal do operador ainda filtra por ela. Mantida e sincronizada por trigger, sem risco de divergir. Remover exige ajustar `fila_trabalho_screen.dart`. |
| **Lista hardcoded `_postosTrabalhoDisponiveis`** | Foi a origem da divergência de (a), mas substituí-la por um dropdown alimentado da tabela `postos_trabalho` altera o comportamento do ecrã — é refactor, não correção. Recomendado como primeiro passo da fase de arquitetura. |
| **Avisos pré-existentes do analisador** | Fora do âmbito; nenhum tem impacto funcional. |
| **Fase de arquitetura** | Repositórios, uso dos models existentes, widgets partilhados, paginação, *debounce* do realtime. Acordado para depois dos bugs. |

---

## 6. Impacto na aplicação

**Não posso afirmar que não há mudanças visíveis para o utilizador — há, e são intencionais.**
Em todos os casos o comportamento anterior era o desvio, e o novo aproxima-se do que estava
especificado. Mas quem usa a aplicação vai notar diferenças:

### Mudanças que o utilizador vai notar

| Onde | Antes | Agora |
|:---|:---|:---|
| **Postos de Trabalho** | Atribuir operador / manutenção não fazia nada | Funciona; os cartões mostram a ordem em curso e os KPIs valores reais |
| **Cancelar ordem** | Bastava confirmar "Sim" | Exige escrever um **motivo** (botão desativado sem ele) |
| **Ordens canceladas** | Desapareciam do sistema | Permanecem, visíveis no novo filtro "Canceladas", só de consulta |
| **Editar utilizador** | Campo de email editável | *Read-only*, com nota explicativa |
| **Alertas de Incidência** | Acumulavam incidências resolvidas | Só paragens em aberto; a disponibilidade volta a 100% sem incidentes |
| **Relatórios / Dashboard** | Total de concluídas e taxa de prazo inflacionados | Valores mais baixos, mas corretos |
| **Mensagens de erro** | Snackbars genéricos com texto técnico | Mensagens de negócio em português ("Encomenda em WIP Hold: aprove o Line Clearance antes de avançar.") |
| **Ações agora bloqueadas** | Era possível avançar uma ordem em hold, aplicar dois holds, validar clearance sem manutenção | Recusadas com explicação |

> ⚠️ **Sobre os relatórios:** os KPIs vão **descer** face aos valores anteriores. Não é
> regressão — os números antigos estavam inflacionados. Relatórios em
> `historico_relatorios` emitidos antes desta correção contêm valores incorretos.

### Sem impacto

- **Nenhum dado foi perdido.** Todas as migrações foram aditivas, com a única exceção do
  `DROP COLUMN utilizadores.password` — cujo conteúdo era precisamente o problema, e cujos
  valores existem de forma segura no Supabase Auth.
- **Nenhuma alteração de layout ou navegação.**
- **Login e alteração de palavra-passe** continuam a funcionar exatamente como antes
  (só deixaram de gravar uma segunda cópia em claro).
- **Terminal do operador e portal do cliente** mantêm-se funcionais: a coluna de texto de
  que dependem continua a existir e sincronizada.

### Nota sobre o diff

`gestao_utilizadores_screen.dart` mostra ~254 linhas alteradas em `git diff`, mas a maioria
são **alterações pré-existentes não commitadas** que já estavam na árvore de trabalho no
início da sessão (commit `7cd2c26`, *"alteracoes na gestao de utilizadores"*). A minha
contribuição nesse ficheiro limita-se ao email *read-only* e à assinatura de
`_atualizarUtilizador()`.
