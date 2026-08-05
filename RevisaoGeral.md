# Revisão Geral do Projeto

**Data:** 2 de agosto de 2026
**Âmbito:** revisão transversal de bugs, segurança, estrutura de código e dívida técnica em todo o projeto.
**Nota:** esta análise **não** inclui funcionalidades novas. Cobre apenas o que existe e o que precisa (ou não) de ser melhorado.

**Estado base no momento da análise:**

| Verificação | Resultado |
|---|---|
| `flutter test` | 194 testes, todos passam |
| `flutter analyze` | 41 issues — 0 errors, 2 warnings, 39 infos |
| Advisors de segurança do Supabase | 12 ERROR + 8 WARN |

Esta revisão fecha o ciclo de análise por módulos (`dashboard_admin`, `terminal_operador`, `portal_cliente`) e cobre sobretudo o que ficou **fora** desses três: `main.dart`, `auth_service.dart`, `login_screen.dart`, `registo_screen.dart`, `core/`, a base de dados e a infraestrutura de testes.

---

## 1. Segurança — ✅ RESOLVIDO (2 de agosto de 2026)

> Todos os pontos desta secção foram corrigidos, exceto 1.5 (toggle manual na consola).
> Advisors de segurança: **0 ERROR, 7 WARN** — eram 12 ERROR e 8 WARN. Os 7 restantes são deliberados e estão justificados em [10.7](#107-avisos-que-ficam-por-desenho).
> O detalhe está em [10. Sessão 1 — RLS e segurança da base de dados](#10-sessão-1--rls-e-segurança-da-base-de-dados).

### 1.1 RLS desligado em 12 tabelas

Row Level Security não está ativo em nenhuma destas tabelas do schema `public`:

`utilizadores`, `clientes`, `encomendas`, `pedidos_encomenda`, `avaliacoes`, `notificacoes`, `incidencias`, `historico_producao`, `fases_padrao`, `tipos_produto`, `postos_trabalho`, `reason_codes`

**Porque é que isto é grave.** A anon key está compilada em [supabase_config.dart:8](lib/core/supabase_config.dart#L8) e é pública por natureza — vai no bundle web e dentro do APK, qualquer pessoa a extrai. Sem RLS, essa chave dá acesso direto e total à API REST:

```
GET   /rest/v1/clientes                              -> carteira de clientes completa
GET   /rest/v1/encomendas                            -> todas as encomendas de todos os clientes
PATCH /rest/v1/utilizadores?utilizador_id=eq.<id>    -> {"perfil":"Admin","estado_conta":"Ativo"}
```

O último pedido promove qualquer utilizador registado a administrador, sem passar pela aplicação.

**Consequência para o trabalho já feito.** Todo o controlo de acesso da aplicação vive na UI. As correções de identidade por chave estrangeira feitas no `portal_cliente` (usar `clientes.utilizador_id` em vez de comparar nomes) impedem um cliente de ver dados errados *através da app* — mas não impedem ninguém de contornar a app por completo. Enquanto o RLS estiver desligado, essas correções são de correção funcional, não de segurança.

Este item foi marcado como *deferred* na análise do `portal_cliente`. Continua a ser o item nº1 do projeto, acima de qualquer outro deste documento.

### 1.2 Política RLS permissiva em `historico_relatorios`

A tabela `historico_relatorios` tem a política `Permitir leitura e escrita para todos` aplicada a `ALL` com `USING (true)` e `WITH CHECK (true)`. Tem RLS ligado, mas a política não filtra nada — leitura e escrita livres para qualquer role.

### 1.3 Bucket público `relatorios` permite listagem

O bucket `relatorios` é público e tem uma política SELECT ampla em `storage.objects` (`Permitir Leitura Pública de Relatorios`) que permite **listar** todos os ficheiros, não apenas aceder a um objeto por URL conhecido. Relatórios de produção de todos os clientes ficam enumeráveis por quem tenha a anon key. O acesso por URL direto não precisa desta política.

### 1.4 Funções `SECURITY DEFINER` executáveis por `anon`

Quatro funções correm com os privilégios do dono e são chamáveis sem sessão iniciada:

| Função | Avaliação |
|---|---|
| `rastrear_encomenda(p_codigo text)` | Intencional — suporta o rastreio público. Manter. |
| `ligar_cliente_utilizador()` | Sem argumentos, `SECURITY DEFINER`, chamável por `anon`. Revogar `EXECUTE` a `anon`. |
| `ligar_utilizador_cliente()` | Idem. Liga identidades — não deve ser acessível a anónimos. |
| `sync_fase_posto_texto()` | Parece ser função de trigger. Não deve estar exposta via `/rest/v1/rpc/`. |

### 1.5 Proteção contra passwords comprometidas desativada

O Supabase Auth pode validar passwords contra a HaveIBeenPwned. Está desligado. Ativação é uma opção de configuração, sem alterações de código.

---

## 2. Bugs de código — ✅ RESOLVIDO (2 de agosto de 2026)

> Todos os pontos desta secção foram corrigidos. Estado após as correções:
> **197 testes passam** (+3), **`flutter analyze`: 33 issues, 0 errors, 0 warnings** (eram 41 com 2 warnings).
> O detalhe do que foi feito em cada ponto está em [9. Resoluções aplicadas](#9-resoluções-aplicadas).

### 2.1 `lib/services/auth_service.dart`

Este ficheiro ficou fora de todas as revisões por módulo. É o único do projeto com *warnings* reais do analisador.

| Local | Problema |
|---|---|
| [auth_service.dart:68](lib/services/auth_service.dart#L68) | `session.user != null` é sempre verdadeiro — `Session.user` é não-nullable. Condição morta. |
| [auth_service.dart:70](lib/services/auth_service.dart#L70) | `session.user!` — o `!` não tem efeito, pela mesma razão. |
| [54](lib/services/auth_service.dart#L54), [103](lib/services/auth_service.dart#L103), [120](lib/services/auth_service.dart#L120), [122](lib/services/auth_service.dart#L122) | Quatro `print()` em código de produção. São os únicos do projeto — todo o resto usa `debugPrint`. `print` continua a escrever no output em release. |
| [auth_service.dart:37-39](lib/services/auth_service.dart#L37-L39) | `try { ... } catch (e) { rethrow; }` não faz nada. Remover o bloco. |

**Erros indistinguíveis.** [`obterUtilizadorPorId`](lib/services/auth_service.dart#L44) apanha tudo e devolve sempre `'Erro ao carregar dados do perfil do utilizador.'`. Um utilizador autenticado sem linha na tabela `utilizadores` (o `.single()` rebenta) fica indistinguível de uma falha de rede. Para o utilizador e para quem faz suporte, são o mesmo ecrã.

**Sessão fica aberta em falha de perfil.** Em [`login()`](lib/services/auth_service.dart#L27), se `obterUtilizadorPorId` falhar, a exceção sobe sem `logout()`. O `signInWithPassword` já foi bem-sucedido, portanto a sessão Supabase fica ativa e persistida enquanto a UI diz que o login falhou. Ao reabrir a app, `verificarSessaoAtiva()` encontra essa sessão. O travão de `estado_conta` [na linha 31](lib/services/auth_service.dart#L31) faz logout corretamente; este caminho não.

**Fora do padrão da camada de dados.** `AuthService` é a única classe de acesso a dados que não estende `BaseRepository` nem usa `guarda()`. Lança `Exception` cru, obrigando [login_screen.dart:95](lib/screens/login_screen.dart#L95) a limpar a mensagem com `replaceAll('Exception: ', '')` — existe `descreverErro` em [estado_erro.dart](lib/widgets/estado_erro.dart) exatamente para isto.

### 2.2 `lib/screens/registo_screen.dart`

**`BuildContext` através de async gaps.** [Linhas 82 e 86](lib/screens/registo_screen.dart#L82) usam `ScaffoldMessenger.of(context)` depois de `await`, sem verificação de `mounted`. São os dois únicos `use_build_context_synchronously` que restam no projeto — todos os outros já foram corrigidos nas revisões anteriores. O bloco `finally` na [linha 90](lib/screens/registo_screen.dart#L90) já faz a verificação; os `catch` não.

**`perfil` usado como estado de aprovação.** [Linhas 44-51](lib/screens/registo_screen.dart#L44-L51) inserem `'perfil': 'Pendente'` e **não escrevem `estado_conta`**. Mas `'Pendente'` não é um perfil válido:

- `PerfilUtilizador.desdeTexto('Pendente')` cai no `default` e devolve `desconhecido`
- `PerfilUtilizador.desconhecido.valorBd` devolve `'Operador'`
- `PerfilUtilizador.desconhecido.etiqueta` devolve `'Funcionário'`

Ou seja, uma conta acabada de registar aparece na gestão de utilizadores como "Funcionário". O campo `perfil` está a codificar aprovação, papel que pertence a `estado_conta` — que existe, tem enum próprio ([utilizador_model.dart:47](lib/models/utilizador_model.dart#L47)) e falha fechado em `pendente`. Dois campos a representar o mesmo conceito de formas inconsistentes.

**Falha parcial deixa conta órfã.** O registo são dois passos do lado do cliente: `signUp` no Auth, depois `insert` em `utilizadores`. Se o segundo falhar, fica uma conta no Auth sem linha de perfil. O utilizador não consegue registar-se de novo (o email já existe no Auth) nem iniciar sessão (não há perfil). Não há recuperação pela aplicação. Devia ser uma RPC transacional ou um trigger em `auth.users`.

**Validação fraca.** O email só é validado como não-vazio — sem verificação de formato. A password não tem campo de confirmação.

**Acesso direto ao Supabase.** Junto com `operador_shell_screen`, é um dos dois únicos sítios em `lib/screens/` que ainda chamam `Supabase.instance.client` para ler/escrever dados. Todo o resto do projeto já passa por repositórios.

### 2.3 `lib/main.dart`

**Sem tratamento de falha na inicialização.** [`SupabaseConfig.init()`](lib/main.dart#L11) é aguardado antes de `runApp`, sem `try/catch`. Se falhar — rede indisponível no arranque, por exemplo — a aplicação morre com ecrã preto, antes de existir qualquer UI para mostrar o erro.

**Sem sistema de rotas.** Não há `navigatorKey`, `routes` nem `onGenerateRoute`. A navegação é toda `MaterialPageRoute` construído inline. Isto torna manual em cada ecrã tudo o que dependa de navegação global: deep-links, e sobretudo o logout forçado (voltar ao login a partir de qualquer ponto da app).

**Sem captura global de erros.** Não há `ErrorWidget.builder` nem `FlutterError.onError`. Qualquer exceção durante o `build` mostra o ecrã vermelho de erro do Flutter ao utilizador final.

### 2.4 Gestão de sessão

**Ninguém subscreve `onAuthStateChange`.** Se o token expirar ou a sessão for revogada — por exemplo, um administrador desativa uma conta a meio do turno — a aplicação não reage. Fica a mostrar a UI com os dados em cache e a falhar silenciosamente nas queries seguintes, em vez de encaminhar para o login.

O travão `estado_conta != ativo` só corre em dois momentos: no login e no arranque (`verificarSessaoAtiva`). O [`operador_shell_screen`](lib/screens/terminal_operador/operador_shell_screen.dart#L85) é o único ecrã que vigia o perfil em tempo real, através de um stream próprio — comportamento correto que não foi generalizado aos outros dois módulos.

---

## 3. Estrutura de código

### 3.1 Ecrãs do `dashboard_admin` por partir

| Ficheiro | Linhas |
|---|---|
| [painel_controlo_screen.dart](lib/screens/dashboard_admin/painel_controlo_screen.dart) | 1761 |
| [informacoes_clientes_screen.dart](lib/screens/dashboard_admin/informacoes_clientes_screen.dart) | 1230 |
| [criar_encomenda_screen.dart](lib/screens/dashboard_admin/criar_encomenda_screen.dart) | 1100 |
| [gestao_utilizadores_screen.dart](lib/screens/dashboard_admin/gestao_utilizadores_screen.dart) | 1024 |

Quatro ficheiros, 5115 linhas — cerca de 30% de todo o `lib/`. O `portal_cliente` e o `terminal_operador` foram reestruturados nas revisões anteriores; o `dashboard_admin` teve a camada de dados extraída para repositórios, mas a UI não foi partida. É a maior dívida estrutural que resta.

### 3.2 Poucos widgets extraídos

A pasta [lib/screens/dashboard_admin/widgets/](lib/screens/dashboard_admin/widgets/) tem apenas três ficheiros (`cartao_kpi`, `etiqueta_estado`, `mouse_drag_scroll_behavior`) — nenhum widget foi extraído dos quatro ecrãs acima.

Fora do `dashboard_admin` não existe biblioteca de widgets partilhada além de [estado_erro.dart](lib/widgets/estado_erro.dart). Diálogos de confirmação, tabelas ordenáveis, badges de estado e barras de filtro estão reimplementados em cada módulo.

### 3.3 Sem gestão de estado partilhado

Cada ecrã é um `StatefulWidget` com `setState` e a sua própria cópia dos dados. `AuthService` é instanciado de novo em cada sítio que precisa dele (`AuthService()`), portanto o campo `_utilizadorAtual` nunca é partilhado — cada ecrã volta a ir buscar o perfil à base de dados. Não existe uma fonte única de verdade para "quem está autenticado".

### 3.4 Documentos de análise na raiz

Cinco ficheiros markdown na raiz do repositório: `NotasDeAlteracoes.md`, `BUGS_RESOLVIDOS.md`, `ARQUITETURA_REFACTOR.md`, `AlteracoesNoOperador.md`, `AlteracoesNoPortalCliente.md` (mais este). São histórico de trabalho, não documentação do produto. Arrumar em `docs/`, deixando o `README.md` como entrada.

---

## 4. Testes

**194 testes, cobertura desequilibrada.** Cobrem modelos, `estado_erro` e três repositórios. Ficam sem qualquer teste:

- [encomendas_repository.dart](lib/repositories/encomendas_repository.dart) — 431 linhas, o núcleo do negócio: `lancar`, `avancarFase`, `cancelar`, `aplicarWipHold`, `registarIntervencaoTecnica`, `aprovarLineClearance`
- `clientes_repository`, `fluxos_repository`, `utilizadores_repository`, `postos_repository`, `relatorios_repository`
- `pdf_service` (410 linhas), `auth_service`

**Zero testes de widget para ecrãs.** Nenhum ecrã tem teste.

**`RecarregadorDebounced` sem testes.** [realtime.dart](lib/core/realtime.dart) tem lógica de temporização não trivial — aresta inicial imediata, teto de rajada, proteção contra recarregamentos sobrepostos e reentrância no `finally`. É exatamente o tipo de código que se parte em silêncio numa alteração futura e só dá sinal em produção.

**Sem CI.** Não existe `.github/workflows`. Nada garante que `flutter analyze` e `flutter test` corram antes de um commit ou merge.

---

## 5. Menor

**Lints (41 no total, nenhum error):**

| Tipo | Nº | Nota |
|---|---|---|
| `withOpacity` deprecated | ~20 | Trivial: trocar por `.withValues()`. Espalhado por vários ecrãs. |
| `DropdownButtonFormField.value` deprecated | ~15 | Os do `portal_cliente` são **deliberados e documentados** (`initialValue` não reage a mudanças de estado). Os do `dashboard_admin` não foram avaliados — verificar caso a caso antes de mexer. |
| `onReorder` deprecated | 1 | [gestao_fluxos_screen.dart:483](lib/screens/dashboard_admin/gestao_fluxos_screen.dart#L483) — usar `onReorderItem`. |
| `anonKey` deprecated | 1 | [supabase_config.dart:14](lib/core/supabase_config.dart#L14) — usar `publishableKey`. |
| `avoid_print` | 4 | Todos em `auth_service` (ver 2.1). |
| `use_build_context_synchronously` | 2 | Ambos em `registo_screen` (ver 2.2). |
| `unnecessary_null_comparison` / `unnecessary_non_null_assertion` | 2 | Os únicos warnings. Ambos em `auth_service` (ver 2.1). |
| `unnecessary_to_list_in_spreads` | 1 | [postos_trabalho_screen.dart:377](lib/screens/dashboard_admin/postos_trabalho_screen.dart#L377). |

**Outros:**

- `pubspec.yaml` — a `description` tem mojibake (`AplicaÃ§Ã£o de GestÃ£o de ProduÃ§Ã£o`): o ficheiro foi gravado com encoding errado. Versão presa em `1.0.0+1` desde o início.
- A pasta `coverage/` está na raiz apesar de `/coverage/` constar do `.gitignore` — confirmar com `git ls-files coverage` se está a ser versionada.
- Revisar `analysis_options.yaml`: com apenas o `flutter_lints` base, regras como `avoid_print` ficam em `info` e passam despercebidas.

---

## 6. Ordem recomendada

1. **RLS e restantes avisos da base de dados (secção 1).** Primeiro e sozinho. Enquanto o RLS estiver desligado, todo o restante trabalho de segurança é cosmético.
2. **`auth_service.dart` + `registo_screen.dart` (2.1, 2.2).** Cerca de meio dia. Fecha o último módulo por rever e elimina os 2 únicos warnings e os 2 únicos `use_build_context_synchronously` do projeto.
3. **Robustez do arranque e da sessão (2.3, 2.4).** `try/catch` no init, captura global de erros, `onAuthStateChange` com logout forçado.
4. **Partir os quatro ecrãs grandes do `dashboard_admin` (3.1, 3.2).**
5. **Testes do `encomendas_repository` e do `RecarregadorDebounced`, mais CI (secção 4).** Antes de qualquer funcionalidade nova.
6. **Lints e limpezas (secção 5).** Em qualquer altura; sem urgência.

---

## 7. Decisões pendentes

Duas questões que precisam de resposta antes de avançar:

**7.1 — RLS: quem escreve as políticas?**
As políticas por perfil (administrador: acesso total; operador: leitura de produção e escrita de histórico; cliente: apenas as suas linhas via `clientes.utilizador_id`) podem ser escritas e aplicadas como migração a partir daqui, ou feitas manualmente na consola do Supabase. É preciso decidir qual.

**7.2 — `perfil: 'Pendente'` no registo: intencional?** — ✅ **Decidido a 2 de agosto de 2026.**
Confirmado na base de dados que **nenhuma** linha usa `perfil='Pendente'` (7 utilizadores: 5 Operador, 1 Cliente, 1 Administrador, todos Ativo), logo o custo de migração era zero. Decisão: passar a usar `estado_conta: 'Pendente'` como travão, com `perfil` a conter apenas papéis reais. Aplicado — ver 9.2.

---

## 8. Plano de execução do trabalho restante

**Definido a 2 de agosto de 2026.** Este é o roteiro a seguir entre sessões de trabalho. Substitui a ordem indicativa da secção 6.

### Regras de trabalho

Aplicam-se a tudo o que falta. Existem porque o recurso escasso não é o código — é o contexto disponível numa sessão. Ler o `painel_controlo_screen.dart` inteiro custa cerca de 25 000 tokens; ler os quatro ecrãs grandes e ainda editá-los não cabe numa sessão. A partir do momento em que o contexto é resumido, o trabalho passa a ser feito sobre uma versão comprimida do que já foi visto — que é precisamente quando reaparecem bugs já corrigidos.

1. **Uma unidade de trabalho por sessão, com commit no fim.** O commit é o que permite esquecer o que já foi feito sem perder nada.
2. **Nunca reler um ficheiro grande por inteiro.** Localizar com `grep`, ler por intervalo de linhas.
3. **Nunca misturar mover com alterar no mesmo passo.** Uma extração pura verifica-se com `flutter analyze` + `flutter test`. Se levar correções à boleia, deixa de ser verificável e passa a precisar de revisão manual linha a linha.
4. **Registar o resultado neste ficheiro no fim de cada sessão**, para a sessão seguinte não ter de redescobrir o contexto.

### Sequência

| # | Sessão | Secção | Estado |
|---|---|---|---|
| 1 | RLS + advisors + trigger de registo | 1 | ✅ concluída (2 ago 2026) |
| 2 | Testes do `encomendas_repository` + `RecarregadorDebounced` + CI | 4 | ✅ concluída (3 ago 2026) |
| 3 | `painel_controlo` — extrair os 5 diálogos (1761 → ~850 linhas) | 3.1 | ✅ concluída (3 ago 2026) — 1761 → 1053 |
| 4 | `painel_controlo` — extrair cartão de ordem e botões de ação (~850 → ~450) | 3.1 | ⬜ |
| 5 | `gestao_utilizadores` (1024 → ~400) | 3.1 | ⬜ |
| 6 | `informacoes_clientes` (1230 → ~450) | 3.1 | ⬜ |
| 7 | `criar_encomenda` (1100 → ~450) | 3.1 | ⬜ |
| 8 | Promover widgets a partilhados, instância única de `AuthService`, lints, arrumar `docs/` | 3.2, 3.3, 3.4, 5 | ⬜ |

**Porquê o RLS primeiro.** É trabalho de base de dados: custa quase zero contexto — são migrações SQL, sem leitura de ficheiros Flutter. É o item de maior risco do projeto e o mais barato de executar.

**Porquê testes antes de refatorar.** Não existe um único teste que cubra `lancar`, `avancarFase` ou `cancelar`. Sem a sessão 2, as sessões 3 a 7 refatoram 5115 linhas de UI que chamam essas funções sem nada que sinalize uma regressão.

### Decisões estruturais tomadas

**Ecrã a ecrã, não passagem transversal primeiro.** Extrair widgets partilhados antes de partir os ecrãs seria desenhar a abstração a partir de um único exemplo. Regra adotada: um widget nasce dentro do módulo onde é usado e **só sobe para `lib/widgets/` à segunda ocorrência real** (sessão 8, com a duplicação já visível).

**Só extração — sem gestão de estado.** Introduzir Provider ou Riverpod em 5115 linhas de UI sem testes de widget é o item de maior risco e menor retorno do documento. O problema concreto da secção 3.3 não precisa disso: é `AuthService` instanciado de novo em quatro sítios, cada um a reler o perfil da base de dados. Resolve-se com uma instância única e cache do perfil da sessão (sessão 8). A gestão de estado a sério fica como decisão separada, para quando os ecrãs já forem pequenos o suficiente para a mudança ser avaliável.

**Corte escolhido para o `painel_controlo`.** O ficheiro não é grande por ter muitos widgets (tem 5 métodos `Widget _`), mas por causa dos diálogos inline: `_abrirDialogWipHold` (479-613), `_abrirDialogRegistoTecnico` (613-804), `_abrirDialogLineClearance` (804-1007), `_abrirDialogHistorico` (1007-1145) e `_abrirDialogEditar` (1803-fim) somam cerca de 900 das 1761 linhas. Cada um tem estado próprio e fronteira óbvia — é o corte mais limpo que existe.

### Este é o último documento de análise

As secções 1 a 5 consolidam o backlog de **todas** as análises feitas (`dashboard_admin`, `terminal_operador`, `portal_cliente` e esta revisão transversal). Fechadas as sessões 1 a 8, não fica análise pendente e o trabalho passa a ser de funcionalidades novas. Duas ressalvas: a secção 4 (testes) nunca fica "completa", fica suficiente; e a proteção contra passwords comprometidas (1.5) é um toggle na consola do Supabase, que tem de ser ligado manualmente.

---

## 9. Resoluções aplicadas

**Data:** 2 de agosto de 2026. Âmbito: toda a secção 2 (bugs de código). As secções 1, 3, 4 e 5 continuam por resolver.

### 9.1 `auth_service.dart` reescrito

- Passou a **estender `BaseRepository`** e a envolver as operações em `guarda()`. Deixa de lançar `Exception` cru: todas as falhas saem como `RepositoryException` com texto de negócio.
- **Condição morta e `!` inútil removidos** — `verificarSessaoAtiva` passou a verificar apenas `currentSession == null` e usa `sessao.user.id` diretamente. Eram os 2 únicos *warnings* do projeto.
- **4 `print()` eliminados.** Eram os únicos do projeto; o diagnóstico agora vem da mensagem da própria exceção.
- **`try/catch/rethrow` vazio removido.**
- **`obterUtilizadorPorId` passou a usar `maybeSingle`**, distinguindo "credencial sem perfil associado" (mensagem própria, que encaminha para o Administrador) de falha de rede.
- **Sessão órfã em falha de perfil corrigida.** Se `obterUtilizadorPorId` falhar depois de um `signInWithPassword` bem-sucedido, `login()` faz agora `logout()` antes de propagar o erro. Antes, ficava uma sessão ativa e persistida enquanto a interface dizia que o login tinha falhado — e a app entrava autenticada no arranque seguinte.
- **`login()` devolve `UtilizadorModel` não-nullable.** O caminho "sem erro mas sem utilizador" deixou de existir, e com ele a verificação redundante no `login_screen`.
- **`logout()` não usa `guarda`** de propósito: é chamado a partir de caminhos de erro (incluindo o do próprio `login`) e uma falha a fechar sessão não pode substituir o erro original.
- **`obterTodosUtilizadores` e `atualizarEstadoUtilizador` removidos** — duplicavam `UtilizadoresRepository.obterTodos` / `alterarEstadoConta` e não tinham uma única utilização.

### 9.2 `registo_screen.dart`

- **Os 2 `use_build_context_synchronously` desapareceram.** Todos os caminhos verificam `mounted` antes de tocar no `context`.
- **`perfil: 'Pendente'` substituído** por `perfil: 'Cliente'` (papel real, o menos privilegiado, que o Administrador ajusta ao aprovar) + `estado_conta: 'Pendente'`, que é o campo que o `AuthService` usa efetivamente como travão de login. O campo `perfil` deixou de codificar aprovação.
- **Acesso ao Supabase movido para `UtilizadoresRepository.registarPedidoDeAcesso`** — o ecrã deixou de ser um dos dois últimos em `lib/screens/` a chamar `Supabase.instance.client` para ler/escrever dados.
- **Conta órfã tratada.** Se o `insert` falhar depois do `signUp`, a sessão é fechada e a mensagem encaminha explicitamente para o Administrador, em vez de sugerir nova tentativa — que nunca poderia funcionar, porque o email já existe no Auth. A eliminação da causa (RPC transacional ou trigger em `auth.users`) fica para o trabalho da secção 1, que já mexe na base de dados.
- **A sessão aberta pelo `signUp` é fechada.** Uma conta pendente de aprovação não pode ficar autenticada.
- **Validação de e-mail por formato** e **campo de confirmação de palavra-passe** adicionados. Um engano a escrever a password só se descobria no primeiro login, que falha sem explicação possível porque a conta até existe.
- Campos passam a ficar desativados durante a submissão.

### 9.3 `main.dart`

- **`SupabaseConfig.init()` protegido com `try/catch`.** Em caso de falha, arranca um `_AppArranqueFalhado` com mensagem legível em vez de morrer com ecrã preto. O detalhe técnico só aparece em `kDebugMode`.
- **`ErrorWidget.builder`** substitui o ecrã vermelho do Flutter em release por um aviso contido. Em debug, o ecrã vermelho mantém-se — é útil a quem está a desenvolver.
- **`FlutterError.onError`** encadeado sobre o anterior, para registo dos erros não tratados.
- **`navigatorKey` e `scaffoldMessengerKey` globais** adicionados, o que torna possível navegar e mostrar mensagens a partir de código que não pertence a nenhum ecrã.

### 9.4 Perda de sessão involuntária

Criados dois ficheiros:

- **`lib/core/sessao.dart` — `VigilanteSessao`.** Subscreve `onAuthStateChange` e, quando a sessão termina sem ser a pedido, faz `pushAndRemoveUntil` para o login com a mensagem "A sua sessão terminou. Inicie sessão novamente.". Cobre token expirado e conta desativada pelo Administrador a meio do turno — situações em que a app ficava a mostrar dados em cache e a falhar em silêncio nas queries seguintes.
- **`lib/core/sessao_local.dart` — `SessaoLocal`.** Distingue o término pedido pela aplicação (botão de logout, `signOut` após `signUp`) do involuntário. Sem isto, cada logout normal daria uma navegação a mais e uma mensagem de erro que não corresponde a nada. É uma **marca temporal com janela de 5 segundos**, não um booleano, para não ficar presa: se o `signOut` falhar a meio, expira sozinha em vez de mascarar a perda de sessão seguinte.

O travão de `estado_conta` do `AuthService` continua a existir e a correr no login e no arranque; o vigilante cobre o intervalo entre os dois.

### 9.5 `login_screen.dart`

- `replaceAll('Exception: ', '')` substituído por **`descreverErro`**, que já existia em `estado_erro.dart` para este efeito.
- Verificação de `utilizador == null` removida (`login()` já não devolve `null`).
- **`_redirecionarPorPerfil` passou a `Future<void>`** e o `logout()` do caso `desconhecido` é agora **aguardado**. Antes era *fire-and-forget*: a sessão podia ficar aberta e a conta entrava sozinha no arranque seguinte, apesar de não ter perfil válido.

### 9.6 Testes

Adicionado `test/core/sessao_local_test.dart` — 3 testes que cobrem a marca ausente, a marca consumida e o facto de a marca servir apenas uma vez (um segundo `signOut`, este involuntário, não pode aproveitar a marca do primeiro).

**Total: 197 testes, todos a passar.**

---

## 10. Sessão 1 — RLS e segurança da base de dados

**Data:** 2 de agosto de 2026. Âmbito: secção 1 completa. Resultado: **0 ERROR nos advisors** (eram 12), **197 testes a passar**, `flutter analyze` com 33 issues e 0 warnings.

### 10.1 Migrações aplicadas

| Migração | O que faz |
|---|---|
| `rls_funcoes_auxiliares_perfil` | Funções `perfil_atual()`, `e_admin()`, `e_operador()`, `e_pessoal()`, `cliente_atual_id()` |
| `rls_politicas_por_perfil` | Políticas de todas as tabelas, criadas **antes** de ligar o RLS |
| `rls_ativar_e_corrigir_relatorios` | `enable row level security` nas 12 tabelas + substituição da política permissiva de `historico_relatorios` |
| `rls_travao_autopromocao_e_ajuste_selects` | Triggers `impedir_autopromocao` e `forcar_registo_pendente`; restrição dos `select` de `pedidos_encomenda` e `avaliacoes` |
| `seguranca_storage_e_revogacao_rpc` | Políticas do bucket `relatorios`; revogação de `EXECUTE` em 3 funções de trigger |
| `criar_perfil_no_registo_auth` | Trigger em `auth.users` que cria a linha de perfil na mesma transação da credencial |
| `revogar_execute_triggers_novos` | Revogação de `EXECUTE` nas funções de trigger criadas nesta sessão |

Rollback, caso algum ecrã fique vazio: `alter table public.<tabela> disable row level security;`

### 10.2 Modelo de acesso

As funções auxiliares são `SECURITY DEFINER` **de propósito**: leem `utilizadores`, que também tem RLS. Se fossem `INVOKER`, a política de `utilizadores` chamaria uma função que lê `utilizadores` — recursão infinita.

Todas exigem `estado_conta = 'Ativo'`. O travão de aprovação que só existia no `AuthService` passa a existir **também no servidor**: uma conta pendente ou inativa não obtém privilégio nenhum, mesmo contornando a aplicação.

| Tabela | Administrador | Operador | Cliente | Anónimo |
|---|---|---|---|---|
| `utilizadores` | tudo | lê todos | só a própria linha | — |
| `clientes` | tudo | lê | lê/edita a própria | — |
| `encomendas` | tudo | lê + atualiza | lê as suas | — |
| `historico_producao` | tudo | lê + insere em nome próprio | — | — |
| `incidencias` | tudo | lê/insere/atualiza | — | — |
| `pedidos_encomenda` | tudo | — | lê/submete os seus | — |
| `avaliacoes` | lê + gere | — | lê/submete as suas | — |
| `notificacoes` | tudo | — | as suas | — |
| `tipos_produto`, `fases_padrao` | escreve | lê | lê | — |
| `reason_codes`, `postos_trabalho` | escreve | lê | — | — |
| `historico_relatorios` | tudo | lê + emite | — | — |

O rastreio público continua a funcionar sem sessão porque `rastrear_encomenda` é `SECURITY DEFINER` e ignora as políticas. É a **única** porta que o anónimo tem, em vez de ter a tabela `encomendas` inteira.

### 10.3 Escalada de privilégios — encontrada e tapada

O RLS decide que **linhas** cada um vê e altera, não que **colunas**. A política de `utilizadores` permite (e tem de permitir) que cada um corrija o seu próprio nome — o que deixava a porta aberta a:

```sql
update public.utilizadores set perfil = 'Admin' where utilizador_id = auth.uid();
```

**Confirmado por teste: era aceite.** Corrigido com o trigger `impedir_autopromocao`, que recusa alterações a `perfil`, `estado_conta` e `utilizador_id` a quem não seja administrador. O trigger `forcar_registo_pendente` faz o equivalente no `insert`, para que ninguém se autodeclare `Admin`/`Ativo` no registo.

### 10.4 Storage — pior do que o advisor indicava

O advisor sinalizou que a política de leitura do bucket `relatorios` permitia **listar** todos os ficheiros. Ao inspecionar as políticas, apareceu uma segunda que **nenhum advisor sinalizou**: `Permitir Upload de Relatorios` aceitava o papel `anon`. Qualquer pessoa com a anon key podia **escrever** ficheiros no bucket.

Ambas substituídas por políticas restritas a `e_pessoal()`. Os links já emitidos continuam a funcionar — o acesso por URL direto num bucket público não depende destas políticas.

### 10.5 Conta órfã do registo — causa-raiz eliminada

O registo eram dois passos do lado do cliente: `signUp` no Auth e depois `insert` em `utilizadores`. Na secção 9.2 isto ficou apenas *mitigado* (mensagem a encaminhar para o Administrador).

Agora a linha de perfil é criada pelo trigger `trg_criar_perfil_utilizador` em `auth.users`, **na mesma transação da credencial**: ou existem ambas, ou nenhuma. O nome vai em metadados do `signUp`. A conta nasce sempre `Cliente`/`Pendente`.

Alterações no Dart que isto obrigou:

- `registarPedidoDeAcesso` deixou de inserir em `utilizadores`; passa `data: {'nome_utilizador': nome}` no `signUp`.
- `criarFuncionario` deixou de inserir. A linha já existe (criada pelo trigger como `Cliente`/`Pendente`) e a promoção a `Operador`/`Ativo` passou a ser feita pelo **cliente partilhado**, que é o que tem a sessão do administrador. O cliente temporário está autenticado como o próprio funcionário e o `impedir_autopromocao` recusaria a alteração — que é exatamente o comportamento desejado.

### 10.6 Verificação por impersonação

Cada perfil foi impersonado (`set local role` + `request.jwt.claims`) e testado contra os caminhos reais da aplicação, tudo dentro de transações revertidas.

| Teste | Resultado |
|---|---|
| Anónimo lê `encomendas`, `clientes`, `utilizadores`, `pedidos`, `avaliacoes`, `notificacoes` | 0 linhas em todas |
| Anónimo usa o rastreio público | funciona |
| Admin lê as 13 tabelas | tudo visível |
| Operador lê produção (`encomendas`, `historico`, `incidencias`, `postos`, `fases`, `reason_codes`) | tudo visível |
| Operador lê `pedidos` e `avaliacoes` | **via-os** → política restringida a admin |
| Cliente lê encomendas/pedidos/avaliações de outros | 0 linhas |
| Cliente lê `historico_producao`, `incidencias`, `postos`, `relatorios` | 0 linhas |
| Cliente promove-se a Admin | bloqueado pelo trigger |
| Cliente corrige o próprio nome | permitido |
| Cliente altera a linha de outro utilizador | 0 linhas |
| Cliente avalia em nome de outro cliente | bloqueado pela política |
| Cliente submete pedido próprio | permitido |
| Operador avança fase (RPC `avancar_fase_encomenda`) | permitido |
| Operador aplica WIP Hold (RPC `aplicar_wip_hold`) | permitido |
| Operador regista trabalho em nome de outro | bloqueado |
| Operador apaga encomenda / apaga cliente / altera fluxo | 0 linhas |
| Admin aprova pedido (RPC completa: encomenda + notificação) | permitido |
| Admin cancela ordem, cria cliente, regista relatório, altera perfis | permitido |
| Registo: `insert` em `auth.users` cria perfil `Cliente`/`Pendente` | confirmado |

**Nota metodológica:** o RLS filtra linhas em silêncio no `delete` e no `update` — não lança erro, devolve 0 linhas. Os primeiros testes deram falsos "aceite" por não distinguirem "sem exceção" de "0 linhas afetadas". Foram repetidos com `get diagnostics ... row_count`.

**As 5 RPCs de negócio são `SECURITY INVOKER`**, portanto passaram a correr sujeitas às políticas. Foi por isso que o operador precisou de `update` em `encomendas` e o admin de `update` em `pedidos_encomenda` (o `select ... for update` exige política de `update` mesmo antes de escrever).

### 10.7 Avisos que ficam por desenho

Restam 7 WARN nos advisors, todos deliberados:

- **`rastrear_encomenda`** executável por `anon` — é a porta do rastreio público.
- **`perfil_atual`, `e_admin`, `e_operador`, `e_pessoal`, `cliente_atual_id`** executáveis por `authenticated` — **não podem ser revogadas**: as expressões das políticas de RLS são avaliadas com os privilégios de quem faz a query, pelo que revogar o `EXECUTE` bloquearia todos os acessos. Cada uma devolve apenas informação sobre o próprio chamador e nenhuma aceita argumentos.
- **Proteção contra passwords comprometidas** — toggle na consola do Supabase (*Authentication → Providers → Email*), não acessível pela API. **Fica por ligar manualmente.**

### 10.8 Por verificar na aplicação real

O RLS foi validado ao nível da base de dados, não com a app a correr. Convém abrir os três perfis e confirmar, em particular:

- os **streams de realtime** (perfil do operador, notificações do cliente, listas do painel), que passam a ser filtrados pelas mesmas políticas;
- o ecrã de **gestão de utilizadores** a criar um funcionário, que é o caminho alterado em 10.5 e o único não coberto pelos testes de impersonação.

---

## 11. Impacto funcional das sessões 1 e 2

**Data:** 2 de agosto de 2026. As secções 9 e 10 descrevem o que foi alterado tecnicamente. Esta descreve o que disso **se nota a usar a aplicação**, e o que foi verificado para garantir que o resto não partiu.

### 11.1 Comportamento que mudou de propósito

| Onde | Antes | Agora | Origem |
|---|---|---|---|
| Ecrã de registo | Nome, e-mail, palavra-passe | Passou a ter **campo de confirmação de palavra-passe** e validação de formato do e-mail | 9.2 |
| Registo | A conta ficava autenticada logo após o `signUp` | A sessão é fechada — a conta está por aprovar e não pode ficar autenticada | 10.5 |
| Registo | Conta nascia com `perfil = 'Pendente'`, que a gestão de utilizadores apresentava como "Funcionário" | Nasce `Cliente`/`Pendente` e aparece corretamente como pendente | 9.2 |
| Login | Erro genérico "Erro ao carregar dados do perfil do utilizador" para qualquer falha | Uma credencial sem perfil associado tem mensagem própria, que encaminha para o Administrador; falhas de rede continuam a dizer o que são | 9.1 |
| Login com perfil inválido | A sessão do Auth ficava aberta apesar do erro apresentado | A sessão é fechada | 9.5 |
| Sessão expirada ou conta desativada a meio do uso | A app ficava com os dados em cache e as queries seguintes falhavam em silêncio | Encaminha para o login com "A sua sessão terminou. Inicie sessão novamente." | 9.4 |
| Falha ao arrancar (sem rede) | Ecrã preto, sem explicação | Ecrã "Não foi possível ligar ao servidor" | 9.3 |
| Erro inesperado de interface em release | Ecrã vermelho do Flutter com stack trace | Aviso contido; em debug o ecrã vermelho mantém-se | 9.3 |
| Criar funcionário (admin) | O cliente temporário inseria a linha de perfil | O trigger cria a linha pendente e o cliente do administrador promove-a a `Operador`/`Ativo`. **Resultado final igual** | 10.5 |
| Contas por aprovar | O travão de acesso existia apenas no `AuthService` | Existe também no servidor: uma conta `Pendente` ou `Inativa` não obtém privilégio nenhum, mesmo contornando a aplicação | 10.2 |

### 11.2 Verificado que NÃO mudou

O RLS podia ter deixado ecrãs vazios. Cada restrição foi cruzada com o código que lê a tabela:

| Restrição introduzida | Verificação |
|---|---|
| Operador deixou de ver `pedidos_encomenda` e `avaliacoes` | Só [relatorios_admin_screen](lib/screens/dashboard_admin/relatorios_admin_screen.dart) e [pedidos_clientes_admin_screen](lib/screens/dashboard_admin/pedidos_clientes_admin_screen.dart) as leem — ambos do administrador. Nenhum ecrã do operador perde conteúdo. |
| Cliente deixou de ver `historico_producao`, `incidencias`, `postos_trabalho`, `reason_codes`, `historico_relatorios` | O `PortalClienteRepository` não lê nenhuma dessas tabelas (zero ocorrências). |
| Anónimo deixou de ver todas as tabelas | O único caminho anónimo da aplicação é o rastreio público, que passa pela RPC `rastrear_encomenda` (`SECURITY DEFINER`, ignora as políticas). Testado a funcionar sem sessão. |
| Bucket `relatorios` fechado a `anon` | O upload só parte do ecrã de relatórios do administrador, que cumpre `e_pessoal()`. Os `getPublicUrl` já emitidos continuam válidos — um bucket público não depende destas políticas para servir um URL direto. |
| RPCs de negócio sujeitas ao RLS | As cinco (`avancar_fase_encomenda`, `aplicar_wip_hold`, `aprovar_line_clearance`, `cancelar_ordem`, `aprovar_pedido_encomenda`) foram executadas com o perfil que as usa. Todas passam — ver 10.6. |

### 11.3 Por confirmar com a aplicação a correr

Dois caminhos foram validados por lógica e por impersonação SQL, mas não com a app aberta:

1. **Criar funcionário.** É o único caminho cujo mecanismo interno mudou (10.5). O resultado esperado é idêntico ao anterior, mas é o primeiro sítio a testar.
2. **Streams de realtime** (perfil do operador, notificações do cliente, listas do painel). Passam a ser filtrados pelas mesmas políticas. O Realtime avalia o RLS por ligação, o que não é simulável por SQL.

Rollback, se algum ecrã ficar vazio: `alter table public.<tabela> disable row level security;`

---

## 12. Sessão 2 — testes do `encomendas_repository`, `RecarregadorDebounced` e CI

**Data:** 3 de agosto de 2026. Fecha a sessão 2 da secção 8. Testes: **+37, num total de 234**, todos verdes; `flutter analyze` sem erros nem warnings (33 `info`, os mesmos de antes).

### 12.1 Decisão: lógica pura em vez de mocks do Supabase

O `encomendas_repository` é quase todo construção de queries sobre `PostgrestFilterBuilder`, que é uma classe `final` do `supabase_flutter` — não se estende nem se falsifica sem uma camada de fakes que partiria a cada upgrade do pacote. Em vez disso, extraiu-se a **regra de negócio** do **modo de a escrever no PostgREST**:

- `_aplicarFiltroEstado` foi partido em dois: `EncomendasRepository.condicoesDoFiltro(filtro)` — **estático e puro**, devolve `List<CondicaoEstado>` — e o método privado que se limita a escrever essas condições na query. A precedência entre cancelada, em hold, concluída e em produção passou a ser verificável sem rede.
- `_termoPesquisa` passou a `termoPesquisa` (público estático) — a sanitização da sintaxe do `or()` é o sítio onde uma vírgula escrita pelo utilizador partia a query.

O que **não** fica coberto: as chamadas RPC (`avancarFase`, `cancelar`, `aplicarWipHold`, `aprovarLineClearance`) e os `insert`/`update`. Continuam sem teste automático — a garantia sobre elas é a das RPCs transacionais na base de dados e o teste manual.

### 12.2 Bug encontrado pelos testes: o teto de rajada media tempo real

O `RecarregadorDebounced` usava `DateTime.now()` para saber quanto faltava até ao `tetoEspera`. Um relógio virtual (`fakeAsync`) não mexe no `DateTime.now()`, pelo que o teste do teto mostrava **um único recarregamento numa rajada de 2 segundos** — o teto nunca disparava no teste. Em produção o comportamento estava certo, mas a lógica ficava por verificar para sempre.

Resolvido com `package:clock`: `clock.now()` em vez de `DateTime.now()`. Em produção é exatamente o mesmo relógio; nos testes o `fakeAsync` substitui-o. Duas dependências novas, ambas já presentes na árvore do `flutter_test`: `clock` (runtime) e `fake_async` (dev).

### 12.3 Ficheiros

| Ficheiro | O que tem |
|---|---|
| `test/repositories/encomendas_repository_test.dart` | 18 testes: condições de cada filtro de estado, exclusão mútua produção/concluída, precedência do hold, sanitização e recorte do termo de pesquisa, `TimelineOrdem.vazia` |
| `test/core/realtime_test.dart` | 13 testes: aresta inicial imediata, coalescência de rajada, teto, pedidos sobrepostos, falha que não deixa o recarregador preso, `descartar` idempotente, invariantes das constantes de temporização |
| `test/core/paginacao_test.dart` | 6 testes: a sonda `tamanho + 1` é descartada e é ela que decide o `temMais` |
| `.github/workflows/ci.yml` | `flutter pub get --enforce-lockfile` + `flutter analyze --no-fatal-infos` + `flutter test`, em push e PR para `main` |

**Porquê `--no-fatal-infos`.** O `flutter analyze` devolve código de saída ≠ 0 com qualquer `info`. Com os 33 `info` de deprecações ainda por tratar (secção 5, sessão 8), o CI nascia vermelho e deixava de ser lido. Trava em erros e warnings — dos quais não há nenhum. Retirar a flag na sessão 8, depois de limpar os lints.

### 12.4 Comportamento da aplicação

Nenhuma alteração funcional. A refatoração do filtro produz exatamente as mesmas condições que o `switch` anterior (é isso que os testes de 12.1 fixam) e o `clock.now()` é o relógio do sistema fora de testes.

---

## 13. Sessão 3 — `painel_controlo`: extração dos diálogos

**Data:** 3 de agosto de 2026. Fecha a sessão 3 da secção 8. `painel_controlo_screen.dart`: **1761 → 1053 linhas**. `flutter analyze` sem erros nem warnings (33 `info`, os mesmos de antes); 234 testes verdes.

### 13.1 O que saiu do ecrã

Seis diálogos, em `lib/screens/dashboard_admin/dialogos/`:

| Ficheiro | Devolve | Linhas |
|---|---|---|
| `dialogo_wip_hold.dart` | mensagem de sucesso, ou `null` | 153 |
| `dialogo_registo_tecnico.dart` | mensagem de sucesso, ou `null` | 218 |
| `dialogo_line_clearance.dart` | mensagem de sucesso, ou `null` | 170 |
| `dialogo_historico_ordem.dart` | nada — só lê | 237 |
| `dialogo_editar_ordem.dart` | `EdicaoOrdem(dataEntrega, faseAtualId)`, ou `null` | 116 |
| `dialogo_cancelar_ordem.dart` | motivo escrito, ou `null` | 79 |

O `_construirEventosTimeline` foi com o diálogo do histórico — é a única coisa que o usa.

### 13.2 Contrato adotado: o diálogo devolve, o ecrã reage

Cada diálogo passou de `StatefulBuilder` dentro de uma closure a `StatefulWidget` próprio com um construtor estático `mostrar(...)`. O resultado sai por `Navigator.pop`; o ecrã fica com três linhas por ação:

```dart
final mensagem = await DialogoWipHold.mostrar(context, ...);
if (mensagem == null || !mounted) return;
_mostrarMensagem(mensagem);
_recarregarMantendoPosicao();
```

Foi esta a escolha porque a alternativa — passar `aoMostrarMensagem` e `aoConcluir` como callbacks — mantinha o ecrã acoplado ao interior de cada diálogo e não reduzia nada de fundo.

Quem escreve na base de dados continua a ser o diálogo, **exceto** em editar e cancelar: esses só recolhem a decisão e devolvem-na, porque a gravação mexe no `_isLoading` do ecrã.

Efeito colateral bem-vindo: os `TextEditingController` passaram a ser libertados no `dispose` do `State`. Antes cada botão do diálogo tinha de se lembrar de chamar `dispose()` — e o caminho do erro não o fazia.

### 13.3 Duas mudanças que não são extração pura

1. **`mensagemDeErro`** — o `_limparErro` privado do ecrã subiu para [mensagens.dart](lib/core/mensagens.dart) para poder ser usado pelos diálogos. É a mesma função; o ecrã passou a chamar a partilhada e a sua cópia foi apagada.
2. **Erro do registo técnico** — mostrava `$e` cru (`Exception: ...`); passou a usar `mensagemDeErro(e)`, como todos os outros. Era o único do ficheiro fora do padrão.

### 13.4 Comportamento da aplicação

Sem alterações visíveis, tirando o texto do erro em 13.2.2. Os SnackBars de validação dentro dos diálogos passaram a ser emitidos com o `context` do diálogo em vez do `context` do ecrã — é o mesmo `ScaffoldMessenger` ancestral, logo aparecem no mesmo sítio.

**Por confirmar com a aplicação a correr:** abrir cada um dos seis diálogos no painel de controlo, com uma ordem em produção e outra em hold. É extração, mas nenhum tem teste de widget.
