# Centralized CI/CD workflows

Repositorio privado central de workflows reutilizables para aplicaciones
guardadas bajo una misma cuenta personal de GitHub. Los pipelines pueden
ejecutarse en runners macOS self-hosted o en runners administrados por GitHub
Actions.

## Flujo de una aplicación Flutter

| Estado de la PR | Acción |
| --- | --- |
| Draft (`opened`, `synchronize`, `reopened`, `converted_to_draft`) | Compila Android e iOS sin publicar y conserva los artefactos. |
| Open (`opened`, `reopened`, `ready_for_review`) | Compila el commit actual y publica la beta de iOS en TestFlight y la de Android en el track configurado. No requiere un draft previo. |
| Merge a `main` (`closed` + `merged`) | Promueve ambas betas a producción. |

La versión de la aplicación siempre se obtiene de su `pubspec.yaml` (`version:
2.3.0+47`). Es independiente del tag mayor del pipeline (`@v2`).

Una PR creada directamente como open ejecuta beta sin haber pasado por draft;
también lo hace al usar **Ready for review** sobre una PR draft. Nuevos commits
en una PR que ya está abierta no vuelven a distribuir una beta automáticamente;
esto evita publicar una versión por cada push. Se puede ejecutar de nuevo desde
`workflow_dispatch`. Una ejecución beta es autosuficiente: corre checks, compila
los binarios firmados del commit actual y solo entonces los distribuye.

## Uso desde una app

1. Copiar `templates/flutter/.github/workflows/main.yml` a la app.
2. Sustituir `YOUR_GITHUB_USER/workflows` por tu usuario y el nombre real de
   este repositorio. El template consume el alias compatible `@v2`, nunca
   `@main`.
3. Conservar `actions: read` y `contents: read` en los permisos del caller; beta
   descarga los artefactos producidos dentro de su propia ejecución.
4. Crear en GitHub el environment `beta` y el environment `production`, con sus
   secretos y protecciones.
5. Crear las variables de repositorio `FLUTTER_VERSION` y `XCODE_VERSION` con
   las versiones usadas por la app; no se declaran en el caller y se aplican
   valores por defecto si se omiten.
6. Configurar Fastlane Match en cada app y añadir los Repository Secrets
   `MATCH_PASSWORD` y `MATCH_GIT_BASIC_AUTHORIZATION` para firmar los builds iOS.
7. Añadir `APP_STORE_CONNECT_API_KEY_BASE64`,
   `APP_STORE_CONNECT_ISSUER_ID` y `APP_STORE_CONNECT_KEY_ID`, y preparar en el
   proyecto las lanes `ios beta` y `ios release`, además de las tareas de Gradle
   Play Publisher indicadas en [docs/flutter.md](docs/flutter.md).
8. Elegir `self-hosted` o `github-hosted` al ejecutar manualmente. Para
   `self-hosted`, registrar el Mac con las labels `self-hosted`, `macOS` y
   `ARM64`; `github-hosted` usa `macos-latest` para iOS y `ubuntu-latest` para
   los demás jobs, sin requerir registro.

Los callers concretos para `ride-your-soul`, `artistic` y `estudio-sybellafit`
están en [docs/apps-francisco.md](docs/apps-francisco.md).

## Acceso entre repositorios privados personales

No hace falta una organización. En el repositorio privado central `workflows`,
abrir **Settings → Actions → General → Access**, seleccionar **Accessible from
repositories owned by TU_USUARIO user** y guardar. Las aplicaciones consumidoras
también deben ser privadas y pertenecer a esa misma cuenta.

Por ejemplo, si el usuario es `juanpbedoya`, la referencia será:

```yaml
uses: juanpbedoya/workflows/.github/workflows/main.yml@v2
```

Hay una limitación importante para los runners self-hosted: en una cuenta
personal cada runner registrado a nivel de repositorio queda dedicado a ese
repositorio. El workflow central sí es compartido, pero cada app que use esa
modalidad necesita al menos un runner registrado en **Settings → Actions →
Runners**. Para compartir automáticamente un mismo pool de Macs entre muchos
repositorios sería necesario moverlos a una organización y registrar runners a
nivel de organización. La modalidad `github-hosted` no tiene ese requisito.

## Versionado del pipeline

Los callers usan el alias mayor `@v2`. Las versiones exactas (`v2.0.1`,
`v2.1.0`) permanecen inmutables y el release actualiza `v2` al último cambio
compatible. Así las apps reciben fixes y capacidades compatibles sin modificar
sus repositorios. Solo un breaking change futuro exige cambiar los callers a
`@v3`.

- `PATCH` (`2.0.1`): correcciones compatibles.
- `MINOR` (`2.1.0`): capacidades nuevas compatibles.
- `MAJOR` (`3.0.0`): inputs, comportamiento o requisitos incompatibles.

Para publicar una versión:

1. Actualizar `VERSION` y `CHANGELOG.md` en una PR.
2. Fusionar la PR a `main`.
3. Crear y subir el tag exacto: `git tag v2.0.1` y `git push origin v2.0.1`.
4. El workflow `Release pipeline version` valida que el tag coincida con
   `VERSION` y crea el GitHub Release.
5. El release mueve automáticamente el alias `v2`; las apps no cambian.

Los tags SemVer exactos son inmutables. Únicamente el alias mayor (`v1`, `v2`)
es flotante por diseño.

Las distribuciones beta y production se serializan por repositorio para impedir
que dos promociones compitan. Los builds anteriores sí se cancelan cuando llega
un commit nuevo a la misma PR.

## Organización

```text
.github/
├── workflows/
│   ├── main.yml
│   ├── flutter-build.yml
│   ├── flutter-release.yml
│   ├── release-integration-app-store.yml
│   ├── release-integration-google-play.yml
│   └── pipeline-release.yml
├── actions/flutter/
│   ├── setup/action.yml
│   ├── setup-android-signing/action.yml
│   ├── setup-ios-signing/action.yml
│   ├── setup-xcode/action.yml
│   ├── read-version/action.yml
│   ├── build-android/action.yml
│   ├── build-ios/action.yml
│   ├── build-web/action.yml
│   ├── release-android/action.yml
│   └── release-ios/action.yml
└── CODEOWNERS
templates/flutter/        # main.yml mínimo que vive en cada app
docs/                     # Contratos por tecnología
```

`.github` es la única fuente de verdad. GitHub solo descubre reusable workflows
directamente en `.github/workflows`; las operaciones repetidas a nivel de steps
se organizan como composite actions bajo `.github/actions`.

- `flutter-build.yml`: agrupa jobs explícitos e independientes para checks,
  Android, iOS y Web; todos los seleccionados comienzan en paralelo y cada uno
  se puede reejecutar individualmente.
- `flutter-release.yml`: recibe los artefactos producidos por el build de la
  ejecución beta y coordina los adaptadores `release-integration-*` para App
  Store y Google Play. También puede resolver un build exitoso anterior cuando
  se invoca directamente sin `artifact-run-id`.
- `release-integration-*`: prepara cada job de distribución y delega la
  publicación a las composite actions `release-ios` y `release-android`.
- `main.yml`: autodetección y orquestación; no contiene builds ni publicación.
- `.github/actions/flutter`: preparación del SDK y lectura normalizada de la
  versión de `pubspec.yaml`, además de las operaciones aisladas de build (CI) y
  release (CD), sin duplicar steps.

Las plataformas se autodetectan o se fijan mediante `platforms`. Cada plataforma
tiene un job propio; las no seleccionadas quedan omitidas y no consumen runner.
Los nombres comparten el prefijo `Flutter build /` para mantenerlos agrupados en
la interfaz de Actions.

Las apps llaman únicamente a `.github/workflows/main.yml`. El input
`technology` selecciona la implementación (`flutter` actualmente); agregar otra
tecnología no requiere ampliar el caller de cada proyecto.

El input `runner` acepta `self-hosted` (predeterminado) o `github-hosted`. Con
`github-hosted`, iOS y App Store usan `macos-latest`; validación, checks,
Android, Web y Google Play usan `ubuntu-latest`. Con `self-hosted`, todos los
jobs usan las labels configuradas para el Mac mini. El template incluye el
selector en `workflow_dispatch`; para que también las ejecuciones automáticas
de PR usen GitHub Actions, se configura de forma fija:

```yaml
with:
  technology: flutter
  runner: github-hosted
```

Para Flutter, el dispatcher localiza automáticamente el único `pubspec.yaml` a
una profundidad máxima de dos directorios. `working-directory` solo se indica
cuando el repositorio contiene más de una app Flutter. El stage manual se lee
directamente del evento, por lo que tampoco se pasa desde el caller.

Las plataformas pueden fijarse desde la app:

```yaml
with:
  technology: flutter
  platforms: android,ios
  android-build-format: appbundle
```

`android-build-format` controla los artefactos Android de los builds draft y
beta, y acepta `apk`, `appbundle` o `both` (valor predeterminado).

Si se omite `platforms`, el valor `auto` habilita Android, iOS o Web según los
directorios presentes en el proyecto.

Al incorporar otra tecnología, se crea un directorio propio bajo `templates/`
y documentación separada; los contratos compartidos permanecen en
`.github/workflows/`.
# workflows
# workflows
# workflows
# workflows
# workflows
# workflows
