# Integración de las apps Francisco

Cada repositorio consumidor conserva solamente `.github/workflows/main.yml`.
GitHub exige declarar los eventos en el repositorio donde ocurre la PR; el
dispatcher central se encarga de toda la selección Draft, Beta y Production.

## Caller mínimo

```yaml
name: Mobile pipeline

on:
  pull_request:
    branches: [RAMA_PRINCIPAL]
    types: [opened, synchronize, reopened, converted_to_draft, ready_for_review, closed]
  workflow_dispatch:
    inputs:
      stage:
        required: true
        type: choice
        options: [draft, beta, production]
      runner:
        description: Runner used for this manual execution
        required: true
        default: github-hosted
        type: choice
        options: [self-hosted, github-hosted]

permissions:
  contents: read

jobs:
  ci:
    uses: fly-mode-labs/workflows/.github/workflows/main.yml@v3
    with:
      technology: flutter
      pipeline: ci
      delivery-mode: direct
      runner: ${{ inputs.runner || 'github-hosted' }}
    secrets: inherit

  cd:
    needs: ci
    uses: fly-mode-labs/workflows/.github/workflows/main.yml@v3
    with:
      technology: flutter
      pipeline: cd
      delivery-mode: direct
      runner: ${{ inputs.runner || 'github-hosted' }}
    secrets: inherit
```

The runner selector appears for manual runs. Automatic PR delivery defaults to
`github-hosted`; choosing `self-hosted` is an explicit persistent-runner choice.
Direct delivery only needs `contents: read`; callers
that intentionally keep the default artifact mode must also grant `actions: read`.

El job `ci` valida y compila. El job `cd` espera a que CI termine correctamente
y se encarga únicamente de las publicaciones beta o production. Ambos llaman al
mismo workflow reutilizable con `pipeline: ci` o `pipeline: cd`; los callers
anteriores que no envían este input conservan el comportamiento combinado.

## Valores instalados

| Repositorio | Rama | Ruta autodetectada | Versión actual |
| --- | --- | --- | --- |
| `ride-your-soul` | `master` | `app_ride` | `0.3.1+35` |
| `artistic` | `main` | `app_artistic` | `1.1.7+1014` |
| `booty_factory_admin` | `main` | `app_sybellafit` | `2.7.3+277` |

Los tres callers viven en `.github/workflows/main.yml` y deben usar `@v3`
con los permisos mostrados antes de habilitar beta. El dispatcher encuentra el
único `pubspec.yaml` y obtiene de allí la ruta de la app. Para una tecnología
futura solo cambia `technology`; la lógica se agrega en el dispatcher central
sin duplicarla en las apps.

## Requisitos de distribución

Las apps necesitan Fastlane para iOS, un `fastlane/Matchfile`, los Repository
Secrets `MATCH_PASSWORD` y `MATCH_GIT_BASIC_AUTHORIZATION`, y las credenciales
de cada tienda en los environments `beta`/`production`. Android direct beta
builds and uploads the signed AAB in the same `beta` job. Direct production
promotes the exact `pubspec.yaml` build number from the configured testing track
to `production` without transferring or rebuilding an AAB. If `self-hosted` is
selected, each repository still needs its own registered runner.
Both `beta` and `production` environments require reviewers. iOS callers must
not set `IOS_SOURCE_PROVENANCE_SUPPORTED=true` until their Fastlane lanes enforce
the documented `SOURCE_SHA` TestFlight metadata contract.
