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
  ci:
    uses: Juanpabedoyav/workflows/.github/workflows/main.yml@v3
    with:
      technology: flutter
      pipeline: ci
      runner: ${{ inputs.runner || 'self-hosted' }}
    secrets: inherit

  cd:
    needs: ci
    uses: Juanpabedoyav/workflows/.github/workflows/main.yml@v3
    with:
      technology: flutter
      pipeline: cd
      runner: ${{ inputs.runner || 'self-hosted' }}
    secrets: inherit
```

El selector `runner` aparece al lanzar el workflow manualmente. Las ejecuciones
automáticas de PR siguen usando `self-hosted`. Para ejecutar siempre en GitHub
Actions, incluso en eventos de PR, se puede reemplazar la expresión anterior por
`runner: github-hosted`. El permiso `actions: read` permite que beta descargue
los artefactos producidos por su propio build o por el build draft previo cuando
la PR pasa a **Ready for review**.

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
de cada tienda en los environments `beta`/`production`. Android beta y
producción descargan el AAB firmado del build previo y lo suben directamente
con `r0adkll/upload-google-play`: beta usa el track configurado (`internal` por
defecto) y producción fuerza el track `production`. Ninguna distribución
requiere Flutter ni Gradle. Si se elige `self-hosted`, cada repositorio también
necesita su propio runner registrado.
