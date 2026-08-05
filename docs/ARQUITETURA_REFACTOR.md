# Refactor de Arquitetura — Módulo `dashboard_admin`

> Refactor puro: o comportamento visível para o utilizador **não muda**. Qualquer
> desvio encontrado é sinalizado explicitamente em cada secção.
>
> Baseline: commit `2ec06e5` ("Corrige 8 bugs no modulo dashboard_admin").
> Correções de bugs documentadas em [BUGS_RESOLVIDOS.md](BUGS_RESOLVIDOS.md).

## Contexto

O diagnóstico inicial identificou quatro problemas estruturais nos 10 ecrãs de
`lib/screens/dashboard_admin/` (~9.100 linhas):

1. Os ecrãs chamavam `Supabase.instance.client` diretamente e manipulavam
   `List<dynamic>` / `Map<String, dynamic>` — erros de nome de campo só apareciam
   em runtime.
2. `lib/models/` existia mas não era usado pelos ecrãs admin.
3. Código duplicado: `MouseDragScrollBehavior` em dois ficheiros; `_mostrarMensagem`,
   cartões de KPI, badges de estado e cálculo de iniciais copiados 4 a 8 vezes.
4. Lógica de negócio ("concluída", "atrasada", "em hold") reimplementada de forma
   **diferente** em cada ecrã — a causa raiz do bug (b) já corrigido.

Plano acordado em 4 passos, com `flutter analyze` e validação manual entre cada um.
Componentes partilhados ficam fora de `dashboard_admin`; `terminal_operador` e
`portal_cliente` não são tocados salvo quebra causada pelo próprio refactor.

---

## Passo 1 — Camada de repositórios (`lib/repositories/`)

### Causa

Cada um dos 10 ecrãs conhecia o Supabase. As queries viviam dentro de métodos de
`State`, misturadas com `setState`, e o mesmo `try/catch` com string de erro
escrita à mão estava repetido em todos. Como as queries estavam espalhadas pela UI,
nada impedia que a mesma entidade fosse lida de formas divergentes em ecrãs
diferentes — foi exatamente assim que nasceu o bug (b) dos relatórios.

### Alteração

Sete ficheiros novos (1.030 linhas), organizados por domínio de dados:

| Ficheiro | Responsabilidade |
|:---|:---|
| `base_repository.dart` | Cliente Supabase, `RepositoryException`, tradução de erros, normalização de respostas |
| `encomendas_repository.dart` | Ordens, histórico, incidências, reason codes, as 4 RPCs de transição |
| `fluxos_repository.dart` | Tipologias de produto e roteiros de fabrico |
| `postos_repository.dart` | Postos de trabalho + constantes `EstadoPosto` |
| `clientes_repository.dart` | Carteira de clientes e pedidos do portal B2B |
| `utilizadores_repository.dart` | Contas, perfis, métricas, criação isolada de funcionários |
| `relatorios_repository.dart` | Avaliações, storage do PDF, log de auditoria |

Decisões de desenho:

- **`RepositoryException`** isola os ecrãs do `PostgrestException`. As RPCs de
  produção lançam mensagens de negócio já escritas em português (ex: *"Encomenda em
  WIP Hold: aprove o Line Clearance antes de avançar."*); essas são preservadas
  tal e qual, para poderem ser mostradas diretamente ao utilizador.
- **`SECURITY INVOKER`** mantido nas RPCs — não abrem bypass ao RLS quando este for ativado.
- **Subscrições realtime** passaram a métodos do repositório que devolvem o canal,
  mantendo a gestão do ciclo de vida no ecrã.

### Ficheiros alterados

Os 10 ecrãs de `dashboard_admin`. Nenhum ficheiro fora da pasta.

### Verificação

- `flutter analyze`: **0 erros**. Avisos desceram de 8 para 6 (dois imports mortos
  removidos ao substituir linhas de import); os 6 restantes são pré-existentes e
  fora de `dashboard_admin`.
- `grep` confirmou **zero** ocorrências de `Supabase.instance` ou `_supabase.` nos
  ecrãs admin.
- Balanço: **−614 / +243 → 371 linhas líquidas cortadas** dos ecrãs.

### Comportamento

Sem alterações. Cada método do repositório emite exatamente a mesma query que
estava no ecrã — mesmas colunas, mesmos filtros, mesma ordenação, verificado um a um.

Três pontos onde foi necessário cuidado explícito para *não* mudar comportamento:

1. **`_limparErro()`** — antes testava `e is PostgrestException ? e.message : ...`.
   Passou a testar `RepositoryException`, cujo `toString()` devolve a mesma mensagem
   do servidor. Texto apresentado é idêntico.
2. **Canais realtime do painel** — existiam *dois* canais (`encomendas_painel` e
   `incidencias_painel`) a disparar o mesmo `_carregarDados`. Unidos num só, porque o
   método do repositório subscreve as duas tabelas. Menos uma conexão WebSocket,
   comportamento igual.
3. **`escutarPerfilAtual()`** — o shell lia `user.email` do objeto de sessão; guardado
   antes em variável local, porque o repositório já não expõe o `User`. Mesmo valor.

Acrescentados alguns `if (!mounted) return` antes de `setState` onde não existiam
(`gestao_fluxos`, `gestao_utilizadores`) — protege contra `setState` após `dispose`,
que era um crash latente. Sem efeito visível.

---

## Passo 2 — Models tipados e `EstadoOrdem`

### Causa

**Os 5 models existentes estavam todos quebrados pela mesma razão:** cada campo era
declarado obrigatório e convertido com `as int` / `as String` diretos, quando na base
de dados quase todos aceitam nulo.

| Model | Campo problemático | Consequência |
|:---|:---|:---|
| `EncomendaModel` | `faseAtualId`, `codigoRastreio`, `dataEntrega`, `clienteId` | `json['fase_atual_id'] as int` rebentava em **qualquer ordem concluída** |
| `HistoricoModel` | `encomendaId`, `faseConcluidaId`, `utilizadorId`, `dataConclusao` | rebentava em qualquer registo sem autor |
| `FaseModel` | `nomeFasePadrao`, `ordem`, `tiposProdutoId` | todos anuláveis na BD |
| `IncidenciaModel` | `motivo`, `dataRegisto`, `historicoProducaoId` | só cobria 5 campos, ignorando todo o fluxo de manutenção |
| `UtilizadorModel` | `email`, `perfil` | anuláveis na BD |

Nenhum sobreviveria a dados reais — a explicação de por que estavam mortos.

Em paralelo, o estado de uma ordem era derivado ecrã a ecrã a partir de três colunas
soltas (`cancelada`, `em_suspenso`, `fase_atual_id`), com regras divergentes.

### Alteração

**Novo `lib/models/estado_ordem.dart`** — definição única do estado de uma ordem,
com ordem de precedência explícita: cancelada → em hold → concluída → em produção.
Expõe `etiqueta`, `eFinal`, `contaParaIndicadores` e `estaNaLinha`.

**Os 5 models reescritos** (532 linhas), fiéis ao schema:

- Campos anuláveis na BD são anuláveis no model.
- `EncomendaModel` passou a suportar os campos das junções (`nomeCliente`,
  `nomeProduto`, `nomeFaseAtual`, `postoFaseAtualId`), com conversões tolerantes que
  aceitam objeto **ou** lista de um elemento — os dois formatos que o Supabase devolve.
- `EncomendaModel.estado` e `.incidenciaAtiva` aplicam as regras no model.
- `IncidenciaModel` cobre agora o ciclo completo: registo → intervenção técnica →
  line clearance, com `estaAberta`, `aguardaLineClearance`, `responsavelIntervencao`.
- `UtilizadorModel.iniciais` centraliza um cálculo que estava duplicado em dois ecrãs
  **com resultados diferentes para o mesmo nome**.

**Dois enums extra, não previstos no plano**, que resolvem duplicação real:
`PerfilUtilizador` e `EstadoConta`. As comparações
`perfil == 'admin' || perfil == 'administrador'` estavam repetidas em 4 sítios com
listas ligeiramente diferentes de variantes aceites.

**Novo `TimelineOrdem`** substitui a `List<List<dynamic>>` devolvida pelo repositório,
onde o ecrã tinha de saber que o índice 0 era produção e o 1 incidências.

**Colapsos por eliminação de código defensivo.** Em `postos_trabalho`, quatro helpers
existiam apenas para desembrulhar `Map`/`List` das junções — trabalho que os models
passaram a fazer:

| Helper | Antes | Depois |
|:---|:---|:---|
| `_obterOrdemAtivaDoPosto` | 17 linhas | 6 |
| `_obterIncidenciaAtivaDoPosto` | 12 | 12 (tipado) |
| `_extrairMotivoIncidencia` | 29 | 13 |
| `_extrairNomeRelacao` | 8 | **eliminado** |

### Ficheiros alterados

**Models (5 reescritos + 1 novo):** `estado_ordem.dart` (novo), `encomenda_model.dart`,
`fase_model.dart`, `historico_model.dart`, `incidencia_model.dart`, `utilizador_model.dart`.

**Repositórios (3):** `encomendas_repository.dart`, `fluxos_repository.dart`,
`utilizadores_repository.dart` — passam a devolver tipos.

**Ecrãs admin (5):** `painel_controlo_screen.dart` (−86 linhas), `postos_trabalho_screen.dart`,
`gestao_fluxos_screen.dart`, `relatorios_admin_screen.dart`, `criar_encomenda_screen.dart`.

**Fora de `dashboard_admin` (3):** `login_screen.dart`, `services/auth_service.dart`,
`services/producao_service.dart` — ver secções seguintes.

### Verificação

- `flutter analyze` sobre todo o `lib`: **0 erros, 0 avisos**.
- `painel_controlo_screen.dart` verificado isoladamente após interrupção de rede a
  meio da edição: chaves equilibradas (130/130), zero acessos por mapa remanescentes,
  0 erros e 0 avisos — apenas 4 `info` de depreciações do SDK Flutter
  (`DropdownButtonFormField.value`, `withOpacity`) pré-existentes.
- Acumulado dos passos 1+2: **−1.034 / +880 → 154 linhas líquidas cortadas**.

### ⚠️ Risco identificado no processo: tipagem invisível ao analisador

Vários ecrãs declaravam os campos de estado como `List<dynamic>`, que aceita qualquer
valor. Ao converter os repositórios para devolver models, esses campos passariam a
conter `EncomendaModel` **enquanto o código continuava a ler `enc['codigo_rastreio']`** —
uma expressão que **compila sem erro e falha em runtime** com `NoSuchMethodError`,
completamente invisível ao `flutter analyze`.

Mitigação: tipar primeiro todas as declarações de campo (`List<EncomendaModel>`,
`Map<int, List<FaseModel>>`, etc.), forçando o analisador a expor cada ponto de leitura
antes de os corrigir. Foi o que permitiu localizar e converter todos os acessos com
garantia de cobertura.

Restam 52 acessos por mapa nos ecrãs admin, referentes a **clientes, pedidos,
reason codes e avaliações** — entidades sem model existente, cuja criação não estava
no âmbito deste passo.

### ⚠️ Correção a uma afirmação anterior: os models *eram* usados

Foi afirmado durante o passo 1, com base num `grep` sobre `lib/screens`, que **nenhum**
ecrã usava os models. **Isto estava incompleto.**

O `login_screen.dart` e o `services/auth_service.dart` usam o `UtilizadorModel` por
**inferência de tipo**, sem nomear a classe:

```dart
final utilizador = await _authService.verificarSessaoAtiva();  // -> UtilizadorModel?
final String perfilNormalizado = utilizador.perfil.trim().toLowerCase();
```

Como o nome da classe nunca aparece nesses ficheiros, escaparam ao `grep`. Além disso,
o `auth_service.dart` está em `lib/services`, que tinha sido excluído da busca.

**Consequência:** ao converter `perfil` e `estado_conta` de `String` para enums, o fluxo
de login deixou de compilar em 4 pontos. Correções aplicadas:

- **`login_screen.dart`** — `_redirecionarPorPerfil(String)` passou a
  `_redirecionarPorPerfil(PerfilUtilizador)`, com `switch` exaustivo em vez da cadeia
  de `if` sobre strings. As variantes aceites são exatamente as mesmas:
  `admin`/`administrador` → admin; `operador`/`funcionario`/`funcionário` → operador;
  `cliente` → cliente; qualquer outra → perfil inválido com logout forçado.
- **`auth_service.dart`** — duas comparações `estadoConta.toLowerCase() != 'ativo'`
  passaram a `estadoConta != EstadoConta.ativo`.

Não se trata de alargamento de âmbito: foi uma quebra causada pelo próprio refactor e
a sua correção era obrigatória.

### ⚠️ Regressão de segurança evitada no `EstadoConta`

O `auth_service.dart` usa o estado da conta como **travão de acesso**, em duas posições
(login e retoma de sessão):

```dart
if (perfil.estadoConta != EstadoConta.ativo) {
  await logout();
  throw Exception('A sua conta está pendente de aprovação ou foi inativada...');
}
```

A **primeira versão** do conversor tinha `ativo` como valor por omissão:

```dart
// VERSÃO INICIAL — INSEGURA
static EstadoConta desdeTexto(String? valor) {
  switch ((valor ?? '').trim().toLowerCase()) {
    case 'inativo':  return EstadoConta.inativo;
    case 'pendente': return EstadoConta.pendente;
    default:         return EstadoConta.ativo;   // ← qualquer valor inesperado
  }
}
```

Isto invertia o sentido do travão: um valor não reconhecido na coluna `estado_conta`
(nulo, vazio, ou algo como `'Suspenso'` introduzido no futuro) passaria a ser lido como
`ativo` e **concederia** acesso. O model anterior fazia o contrário — assumia
`'Pendente'` quando o campo vinha vazio (`(json['estado_conta'] ?? 'Pendente')`), e a
comparação `!= 'ativo'` bloqueava.

Corrigido para falhar fechado, invertendo a lógica do `switch`:

```dart
static EstadoConta desdeTexto(String? valor) {
  switch ((valor ?? '').trim().toLowerCase()) {
    case 'ativo':   return EstadoConta.ativo;
    case 'inativo': return EstadoConta.inativo;
    default:        return EstadoConta.pendente;  // ← nunca concede acesso
  }
}
```

Verificação de que não há impacto nos dados reais: a coluna `utilizadores.estado_conta`
é `NOT NULL` com `DEFAULT 'Pendente'` e, confirmado por query à base de dados, os 7
registos existentes contêm **todos** o valor `Ativo` — nenhum cai no ramo por omissão.
O badge de estado na gestão de utilizadores continua portanto a apresentar exatamente
o mesmo texto. A alteração só se manifesta em valores futuros não previstos —
precisamente o caso que deve falhar fechado.

### Comportamento

Sem alterações visíveis. Mesmas queries, mesmos textos, mesma navegação.

Uma nota sobre `producao_service.dart`: continua morto (nenhum ecrã o usa) e mantém os
dois defeitos já identificados — escreve `'types_produtos_id'` (typo que falharia em
runtime) e grava `fase_concluida_id: faseSeguinte.id`, a fase errada. Recebeu apenas
duas correções mínimas de compilação (`?? -1` em dois parâmetros agora anuláveis) para
que o passo 2 fechasse com o analisador limpo. **É o alvo do passo 4**, que o substitui
integralmente pelas regras de negócio centralizadas.

### Validação manual sugerida

1. **Login com os três perfis** (admin, operador, cliente) — área tocada fora de
   `dashboard_admin` e a mais crítica.
2. **Login com conta pendente/inativa** — confirmar que continua a ser bloqueada.
3. **Painel de Controlo** — filtros por estado, badges, progresso, timeline de histórico.
4. **Postos de Trabalho** — ordem em carga por posto e KPIs do topo.
5. **Fluxos Produtivos** — reordenação por arrasto, editar e duplicar fluxo.
