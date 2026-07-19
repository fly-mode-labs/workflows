# Centralized CI/CD workflows

Repositorio privado central de workflows reutilizables para aplicaciones
guardadas bajo una misma cuenta personal de GitHub. Los pipelines se ejecutan
exclusivamente en runners macOS
self-hosted.

## Flujo de una aplicación Flutter

| Estado de la PR | Acción |
| --- | --- |
| Draft (`opened`, `synchronize`, `reopened`, `converted_to_draft`) | Compila Android e iOS sin publicar y conserva los artefactos. |
| Open (`ready_for_review`) | Publica la beta de iOS en TestFlight y la beta de Android en el track configurado. |
| Merge a `main` (`closed` + `merged`) | Promueve ambas betas a producción. |

La versión de la aplicación siempre se obtiene de su `pubspec.yaml` (`version:
2.3.0+47`). Es independiente del tag del pipeline (`@v1.0.0`).

El cambio de draft a open debe hacerse con **Ready for review**. Nuevos commits
en una PR que ya está abierta no vuelven a distribuir una beta automáticamente;
esto evita publicar una versión por cada push. Se puede ejecutar de nuevo desde
`workflow_dispatch`.

## Uso desde una app

1. Copiar `templates/flutter/.github/workflows/main.yml` a la app.
2. Sustituir `YOUR_GITHUB_USER/workflows` por tu usuario y el nombre real de
   este repositorio. El template queda fijado a una versión exacta, nunca a
   `main`.
3. Crear en GitHub el environment `beta` y el environment `production`, con sus
   secretos y protecciones.
4. Preparar en el proyecto las lanes `ios beta` y `ios release`, y las tareas de
   Gradle Play Publisher indicadas en [docs/flutter.md](docs/flutter.md).
5. Registrar el Mac como runner con las labels `self-hosted`, `macOS` y `ARM64`.

Los callers concretos para `ride-your-soul`, `artistic` y `estudio-sybellafit`
están en [docs/apps-francisco.md](docs/apps-francisco.md).

## Acceso entre repositorios privados personales

No hace falta una organización. En el repositorio privado central `workflows`,
abrir **Settings → Actions → General → Access**, seleccionar **Accessible from
repositories owned by TU_USUARIO user** y guardar. Las aplicaciones consumidoras
también deben ser privadas y pertenecer a esa misma cuenta.

Por ejemplo, si el usuario es `juanpbedoya`, la referencia será:

```yaml
uses: juanpbedoya/workflows/.github/workflows/main.yml@v1.0.0
```

Hay una limitación importante para los runners: en una cuenta personal cada
runner registrado a nivel de repositorio queda dedicado a ese repositorio. El
workflow central sí es compartido, pero cada app necesita al menos un runner
registrado en **Settings → Actions → Runners**. Para compartir automáticamente
un mismo pool de Macs entre muchos repositorios sería necesario moverlos a una
organización y registrar runners a nivel de organización.

## Versionado del pipeline

Los callers siempre fijan un tag SemVer exacto, por ejemplo `@v1.0.0`. No usan
`@main` ni un tag flotante como `@v1`; así, una app solo cambia de pipeline
cuando se actualiza deliberadamente su referencia.

- `PATCH` (`1.0.1`): correcciones compatibles.
- `MINOR` (`1.1.0`): capacidades nuevas compatibles.
- `MAJOR` (`2.0.0`): inputs, comportamiento o requisitos incompatibles.

Para publicar una versión:

1. Actualizar `VERSION` y `CHANGELOG.md` en una PR.
2. Fusionar la PR a `main`.
3. Crear y subir el tag exacto: `git tag v1.0.0` y `git push origin v1.0.0`.
4. El workflow `Release pipeline version` valida que el tag coincida con
   `VERSION` y crea el GitHub Release.
5. Actualizar cada app de `@v1.0.0` a la nueva versión mediante una PR.

Los tags publicados se consideran inmutables: no deben eliminarse ni moverse.

Las distribuciones beta y production se serializan por repositorio para impedir
que dos promociones compitan. Los builds draft anteriores sí se cancelan cuando
llega un commit nuevo a la misma PR.

## Organización

```text
.github/
├── workflows/
│   ├── main.yml
│   ├── flutter-build.yml
│   ├── build-job-flutter-quality.yml
│   ├── build-job-flutter-android.yml
│   ├── build-job-flutter-ios.yml
│   ├── build-job-flutter-web.yml
│   ├── flutter-release.yml
│   ├── release-integration-app-store.yml
│   ├── release-integration-google-play.yml
│   └── pipeline-release.yml
├── actions/flutter/
│   ├── setup/action.yml
│   └── read-version/action.yml
└── CODEOWNERS
templates/flutter/        # main.yml mínimo que vive en cada app
docs/                     # Contratos por tecnología
```

`.github` es la única fuente de verdad. GitHub solo descubre reusable workflows
directamente en `.github/workflows`; las operaciones repetidas a nivel de steps
se organizan como composite actions bajo `.github/actions`.

- `flutter-build.yml`: coordina los jobs `build-job-*` para Quality, Android,
  iOS y Web.
- `flutter-release.yml`: coordina los adaptadores `release-integration-*` para
  App Store y Google Play.
- `main.yml`: autodetección y orquestación; no contiene builds ni publicación.
- `.github/actions/flutter`: preparación del SDK y lectura normalizada de la
  versión de `pubspec.yaml` sin duplicar steps.

Las plataformas también se autodetectan por sus directorios. Las tres apps
actuales ejecutarán Android e iOS; el job Web existe pero permanecerá omitido
hasta que una app contenga el directorio `web/`.

Las apps llaman únicamente a `.github/workflows/main.yml`. El input
`technology` selecciona la implementación (`flutter` actualmente); agregar otra
tecnología no requiere ampliar el caller de cada proyecto.

Para Flutter, el dispatcher localiza automáticamente el único `pubspec.yaml` a
una profundidad máxima de dos directorios. `working-directory` solo se indica
cuando el repositorio contiene más de una app Flutter. El stage manual se lee
directamente del evento, por lo que tampoco se pasa desde el caller.

Las plataformas pueden fijarse desde la app:

```yaml
with:
  technology: flutter
  platforms: android,ios
```

Si se omite `platforms`, el valor `auto` habilita Android, iOS o Web según los
directorios presentes en el proyecto.

Al incorporar otra tecnología, se crea un directorio propio bajo `templates/`
y documentación separada; los contratos compartidos permanecen en
`.github/workflows/`.
# workflows
# workflows
# workflows
