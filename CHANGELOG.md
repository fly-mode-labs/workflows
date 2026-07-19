# Changelog

Todos los cambios relevantes de los pipelines se documentan aquí. El proyecto
usa [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- Los checks de Flutter se ejecutan desde el directorio de la aplicación y el
  análisis queda limitado a `lib`, `test` e `integration_test`, evitando
  analizar dependencias descargadas dentro de `build/ios/SourcePackages`.
- El build draft de iOS conserva la firma configurada por la aplicación y ya no
  fuerza `--no-codesign`.

## [1.1.0] - 2026-07-19

### Added

- Input `android-build-format` para generar `apk`, `appbundle` o ambos durante
  los builds draft de Android.

## [1.0.5] - 2026-07-19

### Changed

- Static analysis y tests aparecen al mismo nivel que los builds de Android,
  iOS y Web dentro de una única matriz paralela.

## [1.0.4] - 2026-07-19

### Fixed

- Static analysis y tests se ejecutan dentro de un único job.
- Los checks y los builds de las plataformas seleccionadas comienzan en
  paralelo, sin dependencias innecesarias entre ellos.

## [1.0.3] - 2026-07-19

### Fixed

- Setup del canal stable ya no envía `flutter-version: stable`, evitando el
  error de resolución de `subosito/flutter-action`.

### Changed

- Static analysis y tests son jobs independientes.
- Jobs y steps usan nombres explícitos para Android, iOS, Web y preparación.

## [1.0.2] - 2026-07-19

### Changed

- Build usa una matriz dinámica y solo crea jobs para las plataformas
  seleccionadas; las plataformas omitidas ya no aparecen en la gráfica.
- Builds de Android, iOS y Web se implementan como composite actions separadas.

## [1.0.1] - 2026-07-19

### Fixed

- Referencias anidadas usan rutas completas versionadas para funcionar cuando
  el caller pertenece a otro repositorio privado.
- Selección explícita de plataformas mediante `platforms`, con autodetección
  opcional y validación de directorios.

## [1.0.0] - 2026-07-19

### Added

- Build de artefactos Flutter para PRs draft.
- Distribución beta a TestFlight y Google Play.
- Promoción a producción después del merge.
- Compatibilidad con repositorios privados de cuentas personales.
- Ejecución en runners macOS self-hosted.
- Dispatcher único `main.yml` seleccionado mediante `technology: flutter`.
- Autodetección de la app mediante `pubspec.yaml` y stage desde el evento.
- Módulos separados `flutter-build.yml` y `flutter-release.yml`, con jobs
  explícitos por responsabilidad y plataforma.
- Jobs de build independientes para Flutter Quality, Android, iOS y Web.
- Integraciones de release independientes para App Store y Google Play.
- Automatización ejecutable centralizada bajo `.github`, sin copias generadas.
- Ownership explícito para los pipelines, templates y archivos de versionado.
- Composite actions internas para setup de Flutter y lectura de versión.
