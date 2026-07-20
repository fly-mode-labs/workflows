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
        default: self-hosted
        type: choice
        options: [self-hosted, github-hosted]

permissions:
  actions: read
  contents: read

jobs:
  pipeline:
    uses: Juanpabedoyav/workflows/.github/workflows/main.yml@v2
    with:
      technology: flutter
      runner: ${{ inputs.runner || 'self-hosted' }}
    secrets: inherit
```

El selector `runner` aparece al lanzar el workflow manualmente. Las ejecuciones
automáticas de PR siguen usando `self-hosted`. Para ejecutar siempre en GitHub
Actions, incluso en eventos de PR, se puede reemplazar la expresión anterior por
`runner: github-hosted`. El permiso `actions: read` permite que beta descargue
los artefactos producidos por su propio build.

## Valores instalados

| Repositorio | Rama | Ruta autodetectada | Versión actual |
| --- | --- | --- | --- |
| `ride-your-soul` | `master` | `app_ride` | `0.3.1+35` |
| `artistic` | `main` | `app_artistic` | `1.1.7+1014` |
| `booty_factory_admin` | `main` | `app_sybellafit` | `2.7.3+277` |

Los tres callers viven en `.github/workflows/main.yml` y deben migrarse a `@v2`
con los permisos mostrados antes de habilitar beta. El dispatcher encuentra el
único `pubspec.yaml` y obtiene de allí la ruta de la app. Para una tecnología
futura solo cambia `technology`; la lógica se agrega en el dispatcher central
sin duplicarla en las apps.

## Requisitos pendientes de distribución

Las apps todavía necesitan Fastlane para iOS, un `fastlane/Matchfile`, los
Repository Secrets `MATCH_PASSWORD` y `MATCH_GIT_BASIC_AUTHORIZATION`, Gradle
Play Publisher para Android y credenciales en los environments
`beta`/`production`. Si se elige `self-hosted`, también necesitan un runner
registrado por repositorio. Hasta completar la configuración de distribución
se debe probar únicamente el stage draft.
