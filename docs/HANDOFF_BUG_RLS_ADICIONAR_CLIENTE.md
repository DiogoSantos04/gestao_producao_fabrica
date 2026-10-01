# Handoff — "Adicionar Cliente" no dashboard admin falha com violação de RLS

> **Para quem lê:** sessão de Claude Code **com acesso à base de dados Supabase**
> (MCP do Supabase, `supabase` CLI ou `psql`). A sessão anterior analisou o
> código todo mas **não tem acesso à base de dados** — só a anon key compilada em
> `lib/core/supabase_config.dart:9`. Por isso o diagnóstico está feito do lado do
> Dart e a causa provável está no servidor, onde esta sessão não chega.
>
> **Estado do repositório:** limpo, branch `main`, commit `e1828d1`. **Nada foi
> editado.** A correção é tua.

---

## 1. O bug, tal como o utilizador o vê

No dashboard do administrador, aba **Clientes**, botão de criar cliente: o
formulário aceita os dados e, ao gravar, aparece um SnackBar vermelho:

```
Erro ao criar cliente: new row violates row-level security policy for table "clientes"
```

É o erro `42501` do Postgres, propagado sem tradução: `guarda()` reencaminha
`PostgrestException.message` tal e qual
(`lib/repositories/base_repository.dart:47-50`) e o ecrã imprime-o cru
(`informacoes_clientes_screen.dart:285`).

Ou seja: o `INSERT` em `public.clientes` é recusado pelo RLS para o papel/JWT
que está a executar a operação.

---

## 2. Caminho exato do código (não é preciso procurar)

### 2.1 Formulário — devolve dados, não grava

`lib/screens/dashboard_admin/dialogos/dialogo_cliente.dart`

- `DialogoCliente.mostrar()` (`:59`) abre o formulário e devolve `DadosCliente?`.
- `_validar()` (`:125`): nome e contacto obrigatórios sempre; email e
  palavra-passe (mín. 6) obrigatórios **só quando se cria acesso**.
- `_criarAcesso` (`:85`) nasce `true`. Com ele ligado, `passwordAcesso` vai
  preenchida; desligado, vai `null`.
- `_gravar()` (`:139`) faz `Navigator.pop(context, DadosCliente(...))`.

### 2.2 Ecrã — decide criar vs. atualizar

`lib/screens/dashboard_admin/informacoes_clientes_screen.dart`

`_abrirDialogCliente()` (`:333`) → `_inserirCliente()` (`:248`):

```dart
String? utilizadorId;
if (passwordAcesso != null) {
  utilizadorId = await _utilizadoresRepo.criarCredencialCliente(
    nome: nome, email: email, password: passwordAcesso,
  );
}

await _clientesRepo.criar({
  'nome_cliente': nome,
  'email': email,
  'contacto': contacto,
  'nif': nif,
  'pessoa_contacto': pessoaContacto,
  'morada': morada,
  'ativo': ativo,
  'utilizador_id': ?utilizadorId,   // elemento null-aware (Dart 3.12)
});
```

`_clientesRepo.criar` é um `insert` simples, sem RPC nem `SECURITY DEFINER`
(`lib/repositories/clientes_repository.dart:122-126`):

```dart
Future<void> criar(Map<String, dynamic> dados) {
  return guarda('criar o cliente', () async {
    await client.from('clientes').insert(dados);
  });
}
```

`client` é `Supabase.instance.client` — a sessão do administrador
(`base_repository.dart:26`).

### 2.3 Criação da credencial (passo anterior ao insert)

`lib/repositories/utilizadores_repository.dart:126-180`

`criarCredencialCliente` → `_criarCredencial`, que:

1. cria um `SupabaseClient` **temporário** com `AuthFlowType.implicit`;
2. faz `signUp(email, password, data: {'nome_utilizador': nome})` nesse cliente
   temporário (o trigger `trg_criar_perfil_utilizador` em `auth.users` cria a
   linha de `public.utilizadores` como `Cliente`/`Pendente`);
3. promove essa linha com o **cliente partilhado** (sessão do admin):
   `update utilizadores set nome_utilizador, perfil='Cliente', estado_conta='Ativo'`;
4. devolve `novoUser.id`;
5. `tempClient.dispose()`.

Verificado no SDK instalado (`gotrue 2.26.0`, `supabase 2.14.0`): `_saveSession`
do `GoTrueClient` é **por instância e em memória**, e o cliente temporário não
recebe `asyncStorage`. Portanto **o `signUp` do cliente temporário não substitui
a sessão do administrador no cliente partilhado.** A hipótese "o signUp roubou a
sessão" foi descartada com base nisto — confirma-a se quiseres, mas não é o
caminho principal.

---

## 3. Diagnóstico: o que sabemos e o que falta

O `SELECT` de `clientes` funciona (a lista da carteira carrega no ecrã). O
`INSERT` é recusado. Em Postgres isso significa que o `USING` passa e o
`WITH CHECK` não — ou, muito mais provável, que **não existe política de INSERT
que cubra o administrador** em `public.clientes`.

`RevisaoGeral.md:408` afirma que o teste por impersonação "Admin … cria cliente"
passou. Uma das duas coisas é verdade: ou essa linha nunca cobriu de facto o
`INSERT` (o teste pode ter corrido antes de a política ser restringida), ou a
política existe e o problema é o predicado `e_admin()` devolver `false` para
este utilizador.

O modelo de acesso documentado (`RevisaoGeral.md:336-356`) diz:

| Tabela | Administrador | Operador | Cliente | Anónimo |
|---|---|---|---|---|
| `clientes` | tudo | lê | lê/edita a própria | — |

As funções auxiliares (`e_admin()`, `e_pessoal()`, `e_operador()`, `e_tecnico()`,
`cliente_atual_id()`) são `SECURITY DEFINER` e **todas exigem
`estado_conta = 'Ativo'`**.

Há triggers relevantes: `trg_impedir_autopromocao` (recusa alterações a
`perfil`, `estado_conta`, `utilizador_id` a quem não seja admin),
`trg_forcar_registo_pendente`, `trg_criar_perfil_utilizador`.

**Não existem migrações no repositório** — `supabase/` só tem `functions/`. Todo
o RLS vive apenas no projeto remoto. Projeto: `hnilivakkwvnvgyblmss`.

### 3.1 Teste que separa as duas causas (pedir ao utilizador, 30 segundos)

Criar um cliente com o interruptor **"Criar conta de acesso ao portal"
desligado** (`dialogo_cliente.dart:246`). Nesse caminho não há `signUp` nenhum:
é só o `insert` em `clientes`, com `utilizador_id` ausente.

- **Falha igual** → o problema é puramente a política de `INSERT` em `clientes`
  (ou `e_admin()` falso para esta conta). Nada a ver com o Auth.
- **Funciona** → o `insert` só falha quando leva `utilizador_id` preenchido, e há
  algo no `WITH CHECK` (ou numa política restritiva) que olha para essa coluna.

### 3.2 SQL de diagnóstico

```sql
-- 1. Políticas de clientes, comando a comando
select policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'clientes'
order by cmd, policyname;

-- 2. RLS está ligado? Há política FORCE?
select relname, relrowsecurity, relforcerowsecurity
from pg_class where oid = 'public.clientes'::regclass;

-- 3. A conta do administrador satisfaz o predicado?
select utilizador_id, nome_utilizador, email, perfil, estado_conta
from public.utilizadores
where perfil ilike '%admin%' or email = 'admin@factory.com';

-- 4. Corpo dos predicados (confirmar a grafia exata de `perfil` que aceitam)
select p.proname, pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('e_admin','e_pessoal','e_operador','e_tecnico','cliente_atual_id');

-- 5. Reproduzir o insert como o administrador, dentro de transação revertida
begin;
  set local role authenticated;
  set local request.jwt.claims to '{"sub":"<UUID_DO_ADMIN>","role":"authenticated"}';
  select public.e_admin();                      -- esperado: true
  insert into public.clientes (nome_cliente, email, contacto, nif, pessoa_contacto, morada, ativo)
  values ('TESTE RLS', 't@t.pt', '912345678', '', '', '', true);
rollback;
```

O ponto 4 importa mais do que parece: `_criarCredencial` escreve `'Cliente'` e
`'Operador'` como literais, e `gestao_utilizadores_screen.dart:545` também
grava `'Operador'`/`'Ativo'` hardcoded. Se `e_admin()` comparar com
`'Administrador'` e a conta tiver `'Admin'` (ou vice-versa), o predicado é falso
e **nada** do que o admin escreve passa.

### 3.3 Correção provável (valida os nomes antes de aplicar)

```sql
-- Só se o diagnóstico mostrar que falta o INSERT. Usa o nome de política
-- coerente com as que já existirem na tabela.
create policy "clientes_insert_admin"
  on public.clientes
  for insert
  to authenticated
  with check (public.e_admin());
```

Se a política do administrador existir como `for all` mas apenas com `using` e
**sem** `with_check`, o `INSERT` é recusado apesar de `using` passar: acrescenta
o `with check`, ou substitui por políticas por comando.

---

## 4. Segundo defeito, no mesmo fluxo — tem de ser corrigido junto

`_inserirCliente` cria a credencial **antes** da ficha de cliente. Quando o
`insert` em `clientes` falha (é o que está a acontecer agora), fica atrás:

- uma linha em `auth.users` com aquele email;
- a linha correspondente em `public.utilizadores`.

Consequências práticas:

1. **Cada tentativa falhada queima o email.** Repetir com o mesmo email passa a
   dar `User already registered` (ou, com confirmação de email ligada, um
   utilizador ofuscado cujo `id` não existe em `utilizadores`, e aí o insert
   morre em violação de chave estrangeira em `clientes.utilizador_id`). Pergunta
   ao utilizador quantas vezes tentou e limpa os órfãos:

```sql
-- Contas criadas sem ficha de cliente correspondente
select u.utilizador_id, u.email, u.perfil, u.estado_conta
from public.utilizadores u
left join public.clientes c on c.utilizador_id = u.utilizador_id
where u.perfil = 'Cliente' and c.id is null
order by u.utilizador_id;
```

Apagar em `auth.users` (o cascade limpa `utilizadores`) — **confirmar cada uma
com o utilizador antes de apagar**, porque um cliente legítimo sem ficha na
carteira daria o mesmo resultado nesta query.

2. **O comentário do código está errado sobre o que protege.** Diz
   *"Se falhar, não se chega a criar ficha nenhuma — melhor não ter cliente do
   que ter um cliente que se dizia com acesso e não tem"*
   (`informacoes_clientes_screen.dart:243-247`). O que descreve é o contrário do
   que sucede: falha o segundo passo e sobra a credencial órfã.

3. **O passo 3 de `_criarCredencial` falha em silêncio.** Um `UPDATE` recusado
   pelo RLS afeta 0 linhas e **não levanta erro**. Se a política de
   `utilizadores` não deixar o admin promover a linha, o cliente novo fica
   `Cliente`/`Pendente` e não consegue entrar, sem aviso nenhum. Vale testar esse
   `UPDATE` na mesma transação revertida do ponto 5.

Ordem correta a implementar depois de o RLS ficar resolvido: ou inverter os
passos (criar a ficha, depois a credencial, depois ligar `utilizador_id`), ou —
melhor — fazer a coisa toda numa RPC `SECURITY DEFINER` transacional, como o
resto do projeto já faz para as transições de estado. A segunda opção é a
coerente com a arquitetura.

---

## 5. Contexto do projeto (o suficiente para trabalhares sem reler tudo)

Flutter + Supabase. Raiz: `C:\src\gestao_producao_fabrica`. Quatro perfis:
Administrador (`lib/screens/dashboard_admin/`), Operador (`terminal_operador/`),
Técnico (`terminal_tecnico/`), Cliente (`portal_cliente/`).

Camadas: `core/` (breakpoints, mensagens, formatos, paginacao, temas_cores,
ecra_recarregavel), `models/`, `repositories/` (todo o acesso a dados; erros
traduzidos por `guarda()` para `RepositoryException`), `services/` (auth, PDF,
relatório de turno), `screens/` por perfil.

Transições transacionais vivem em RPCs, nunca no cliente:
`avancar_fase_encomenda`, `aplicar_wip_hold`, `aprovar_line_clearance`,
`cancelar_ordem`, `aprovar_pedido_encomenda`, `aceitar_incidencia`,
`concluir_intervencao_tecnica`, `rastrear_encomenda` (SECURITY DEFINER),
`confirmar_rececao_encomenda`, `obter_email_suporte` (SECURITY DEFINER),
`obter_desempenho_fases`.

Convenções: estado da ordem sai sempre de
`EstadoOrdem.derivar(cancelada:, emSuspenso:, temFaseAtual:)`; paginação no
servidor com linha-sonda (`tamanho + 1`, `PaginaResultado.aPartirDeSondagem`,
`tamanhoPaginaPadrao = 50`); pesquisa com debounce de 300 ms; realtime coalescido
por `RecarregadorDebounced`; `timestamptz` em UTC na base de dados com
`.toLocal()` em toda a apresentação.

CI (`.github/workflows/ci.yml`): `flutter analyze` (falha em `info`) +
`flutter test`. Qualquer alteração ao Dart tem de passar nos dois.

### 5.1 Outros defeitos já mapeados (não são este bug — não os arrastes para a correção)

Registados aqui só para não serem redescobertos:

- Selects sem limite truncados no teto de 1000 do PostgREST, corrompendo KPIs:
  `dashboard_principal_screen.dart:189`, `relatorios_admin_screen.dart:185`,
  `utilizadores_repository.dart obterTodos`.
- Offset de paginação = `list.length`, que o realtime muta:
  `painel_controlo_screen.dart:165`, `informacoes_clientes_screen.dart:144`.
- `dashboard_admin_shell.dart:482` instancia os 10 ecrãs em cada `build` — todos
  os canais de realtime abrem no arranque.
- `dialogo_cliente.dart:106/240-243` grava só `clientes.ativo` e nunca
  `utilizadores.estado_conta`: um cliente "bloqueado" continua a poder entrar.
- `dialogo_cliente.dart:187-190` põe `LengthLimitingTextInputFormatter(9)` antes
  de `digitsOnly`; colar `123-456-789` perde dígitos.
- `dialogo_editar_ordem.dart:105-108`: marcar uma fase como `null` conta como
  concluída sem escrever `data_conclusao` nem linha de histórico — a ordem fica
  invisível em `relatorios_admin_screen.dart:131-156`.
- `encomendas_repository.dart:910` escreve `DateTime.now().toIso8601String()`
  (sem offset) numa coluna `timestamptz`.
- Códigos `TRC-` gerados no cliente, sem verificação de unicidade e com dois
  alfabetos diferentes (`criar_encomenda_screen.dart:197-202`,
  `pedidos_clientes_admin_screen.dart:57-61`).
- `cliente_shell_screen.dart:259-262` fabrica `CLI-2026-` + `hashCode` em vez do
  `clientes.id` real.
- Quatro formatadores de erro diferentes; `terminal_tecnico` mostra `'$e'` cru
  (`fila_manutencao_screen.dart:80`, `dialogo_concluir_intervencao.dart:77`).
- Breakpoints hardcoded (950/900/850/700/650/560) apesar de
  `core/breakpoints.dart`; `_formatarData` reescrito em 5+ ecrãs apesar de
  `core/formatos.dart`.
- Sem realtime nem `EcraRecarregavel` (ficam velhos dentro do `IndexedStack`):
  `gestao_fluxos_screen.dart`, `postos_trabalho_screen.dart`,
  `relatorios_admin_screen.dart`, `pedidos_clientes_admin_screen.dart`,
  `tecnico_shell_screen.dart`.

### 5.2 Notas de segurança a ter em conta ao mexer no RLS

- A anon key está commitada em `lib/core/supabase_config.dart:9`. É pública por
  natureza, mas está no repositório — é a chave que dá acesso à API REST, e é
  por isso que o RLS é a única barreira real.
- O bucket `relatorios` teve políticas permissivas para `anon` (leitura e
  **escrita**), substituídas por `e_pessoal()`. Confirma que continuam restritas
  se tocares em políticas de storage.
- `utilizadores_repository.dart:197` (`registarPedidoDeAcesso`) faz `signUp` no
  cliente **partilhado**, o que abre sessão como o novo utilizador; está mitigado
  por `SessaoLocal.marcarTerminoIntencional()` + `signOut()`, não resolvido.

---

## 6. O que fazer, por ordem

1. Correr o SQL de diagnóstico da secção 3.2 e dizer ao utilizador o que
   aparece — em especial o resultado do ponto 1 (políticas) e do ponto 3
   (`perfil`/`estado_conta` da conta de administrador).
2. Pedir o teste da secção 3.1 (criar cliente com o acesso desligado) para
   confirmar de que lado está a causa.
3. Aplicar a política que faltar, **como migração versionada** —
   `supabase/migrations/`, que hoje não existe e devia. Repetir o insert da
   transação revertida para confirmar.
4. Limpar as contas órfãs da secção 4, uma a uma, com confirmação do utilizador.
5. Só depois tratar a ordem dos passos em `_inserirCliente` (secção 4, ponto
   final). Essa parte é Dart e tem de passar `flutter analyze` + `flutter test`.

Não juntes nada da secção 5.1 a esta correção.
