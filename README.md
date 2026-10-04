# agenteresolve-ci

Quality gates e padrão de engenharia compartilhados dos projetos Agenteresolve.

## Conteúdo

- `docs/quality-standard.md` — o padrão (gates, DoD, convenções).
- `.github/workflows/node-quality.yml` — lint, format, types, unit/integration, coverage, build, e2e opcional, audit.
- `.github/workflows/python-quality.yml` — ruff, mypy, bandit, pytest+cov, pip-audit.
- `.github/workflows/php-quality.yml` — Pint, PHPStan, tests (Postgres), composer audit.
- `.github/workflows/security-scan.yml` — gitleaks, Trivy FS, Semgrep.
- `.github/workflows/docker-build-scan.yml` — build + Trivy image.
- `config/` — `.gitleaks.toml`, `dependabot.yml`, `.pre-commit-config.yaml` de base.

## Uso

Nos repos consumidores, adicione um caller:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  node:
    uses: alex-pimentel/agenteresolve-ci/.github/workflows/node-quality.yml@main
    with:
      package_manager: npm
      coverage: true
  security:
    permissions: { contents: read, security-events: write }
    uses: alex-pimentel/agenteresolve-ci/.github/workflows/security-scan.yml@main
```

Cada repo deve ter scripts `lint`, `format`, `format:check`, `types`, `test`, `test:coverage`, `build` (Node) e publicar cobertura.
