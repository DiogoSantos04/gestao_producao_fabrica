# gestao_producao_fabrica

Aplicação Flutter de gestão de produção industrial com rastreabilidade por ordem
de fabrico. Três perfis de utilização sobre a mesma base de dados Supabase:

| Perfil | Onde vive | O que faz |
| --- | --- | --- |
| Administrador | `lib/screens/dashboard_admin/` | Planeamento e lançamento de ordens, fluxos de produção, postos, clientes, utilizadores e relatórios |
| Operador | `lib/screens/terminal_operador/` | Terminal de chão de fábrica: fila de trabalho, registo de fases, bloqueios e paragens |
| Cliente | `lib/screens/portal_cliente/` | Portal B2B: pedidos de encomenda, rastreio e histórico |

## Arrancar

```bash
flutter pub get
flutter run -d windows   # ou chrome, android, …
```

As credenciais do Supabase estão em `lib/core/supabase_config.dart`.

## Estrutura

```
lib/
  core/           utilitários transversais (temas, formatos, realtime, paginação, sessão)
  models/         modelos de domínio, com fromJson e regras de estado
  repositories/   todo o acesso a dados; erros saem como RepositoryException
  services/       autenticação e geração de PDF
  screens/        um diretório por perfil, com widgets/ e dialogos/ próprios
  widgets/        widgets partilhados por mais do que um perfil
test/             testes de modelos, repositórios, core e widgets
```

Regra de arrumação: um widget sobe a `lib/widgets/` quando é usado por mais do
que um perfil. Enquanto for de um só, fica no `widgets/` desse perfil.

## Verificação

```bash
flutter analyze
flutter test
```

Ambos correm no CI (`.github/workflows/ci.yml`) em cada push e pull request para
`main`, e `flutter analyze` trava também nos `info`.

## Histórico de trabalho

`docs/` guarda as notas de refactor e a lista de bugs corrigidos, referidas a
partir dos comentários do código:

- [docs/ARQUITETURA_REFACTOR.md](docs/ARQUITETURA_REFACTOR.md) — porquê das camadas atuais
- [docs/BUGS_RESOLVIDOS.md](docs/BUGS_RESOLVIDOS.md) — bugs (a) a (f), citados no código
- [docs/AlteracoesNoOperador.md](docs/AlteracoesNoOperador.md) — bugs (A) a (E) do terminal
- [docs/AlteracoesNoPortalCliente.md](docs/AlteracoesNoPortalCliente.md)
- [docs/NotasDeAlteracoes.md](docs/NotasDeAlteracoes.md)

`RevisaoGeral.md` é o plano da revisão geral em curso.
