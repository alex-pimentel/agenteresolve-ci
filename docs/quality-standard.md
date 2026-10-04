# Agenteresolve — Padrão de Qualidade

Mesmo nível de qualidade em **todos** os projetos. Nenhum PR é aceitável se qualquer gate abaixo estiver vermelho ou ausente.

## Gates obrigatórios por stack

| Gate | Node/TS | Python | PHP |
|---|---|---|---|
| Lint | ESLint | ruff check | Pint (`--test`) |
| Format | Prettier (`format:check`) | ruff format `--check` | Pint |
| Análise estática | TypeScript `tsc --noEmit` | mypy | PHPStan (Larastan) |
| Testes unitários | Vitest | pytest | Pest/PHPUnit |
| Testes de integração | Vitest (com serviços via compose) | pytest + compose | Pest com Postgres |
| E2E | Playwright | — | Dusk/Playwright (quando houver UI própria) |
| Cobertura | meta explícita no vitest | `--cov-fail-under` | `--min` |
| Build | `npm run build` | import/compile | `npm run build` + `artisan` |
| Dependências | `npm/pnpm audit --audit-level=high` | `pip-audit` | `composer audit` |
| Segredos | gitleaks | gitleaks | gitleaks |
| Vulnerabilidades | Trivy FS/imagem + CodeQL | Trivy FS + Bandit + CodeQL | Trivy FS + CodeQL |
| SAST | Semgrep | Semgrep + Bandit | Semgrep |

## Workflows reutilizáveis (este repo)

- `node-quality.yml` — lint, format, types, test, coverage, build, e2e (opcional), audit.
- `python-quality.yml` — ruff, mypy, bandit, pytest+cov, pip-audit.
- `php-quality.yml` — Pint, PHPStan, tests (Postgres), composer audit.
- `security-scan.yml` — gitleaks, Trivy FS (SARIF), Semgrep.
- `docker-build-scan.yml` — build + Trivy image (SARIF).

Chamada padrão no repo consumidor:

```yaml
jobs:
  node:
    uses: alex-pimentel/agenteresolve-ci/.github/workflows/node-quality.yml@main
    with:
      working_directory: .
      package_manager: npm
      coverage: true
      run_e2e: true
  security:
    permissions: { contents: read, security-events: write }
    uses: alex-pimentel/agenteresolve-ci/.github/workflows/security-scan.yml@main
```

## Padrões de repositório

- **`.gitleaks.toml`** em todo repo (copiar de `config/gitleaks.toml`).
- **`.github/dependabot.yml`** com os ecossistemas usados (`config/dependabot.yml` como base).
- **`.pre-commit-config.yaml`** (opcional, recomendado) com gitleaks + lint/format locais.
- **`.editorconfig`** e **`.prettierrc`/`ruff`/`pint`** versionados.
- **Scripts npm obrigatórios**: `lint`, `format`, `format:check`, `types`, `test`, `test:coverage`, `build`.
- **Cobertura mínima inicial**: 60% (subir gradualmente). Nunca reduzir a meta.
- **`.env.example`** sempre atualizado; **nenhum** segredo real no git.
- **CodeQL** habilitado por repo (workflow próprio, por linguagem).
- **Dependency Review** em PRs (`dependency-review-action`).
- **Branch protection** em `main`: PR + checks verdes obrigatórios.
- **Conventional Commits** (título do PR e commits).
- **Sem `TODO` silencioso**: abrir issue ou resolver.

## E2E de referência

Repos com UI: Playwright (`playwright.config.ts`), rodando fluxo crítico (ex.: upload → resultado; gerar QR → download). Rodar no CI em PRs que tocam UI.

## Segurança

- gitleaks em `push` e `pull_request` (histórico completo no push).
- Trivy FS sempre; Trivy imagem para repos com Docker.
- Bandit (Python) e Semgrep (todas as stacks) como SAST.
- CodeQL por linguagem. SARIF publicado em Security → Code scanning.
- Nunca printar segredos; nunca commitar `.env`.

## Definition of Done (qualquer mudança)

1. Testes (unit + integração; e2e quando aplicável) verdes e cobrindo o novo comportamento.
2. Lint/format/types/análise estática verdes.
3. Nenhum segredo/vulnerabilidade nova crítica/alta sem mitigação registrada.
4. `README`/`.env.example` atualizados quando o contrato mudar.
5. PR com checks verdes; commits convencionais.
