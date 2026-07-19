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

jobs:
  pipeline:
    uses: Juanpabedoyav/workflows/.github/workflows/main.yml@v1
    with:
      technology: flutter
    secrets: inherit
```

## Valores instalados

| Repositorio | Rama | Ruta autodetectada | Versión actual |
| --- | --- | --- | --- |
| `ride-your-soul` | `master` | `app_ride` | `0.3.1+35` |
| `artistic` | `main` | `app_artistic` | `1.1.7+1014` |
| `booty_factory_admin` | `main` | `app_sybellafit` | `2.7.3+277` |

Los tres callers están instalados en `.github/workflows/main.yml`. El dispatcher
encuentra el único `pubspec.yaml` y obtiene de allí la ruta de la app. Para una
tecnología futura solo cambia `technology`; la lógica se agrega en el dispatcher
central sin duplicarla en las apps.

## Requisitos pendientes de distribución

Las apps todavía necesitan Fastlane para iOS, Gradle Play Publisher para
Android, credenciales en los environments `beta`/`production` y un runner
self-hosted registrado por repositorio. Hasta entonces se debe probar únicamente
el stage draft.
