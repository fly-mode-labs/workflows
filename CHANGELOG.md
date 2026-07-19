# Changelog

Todos los cambios relevantes de los pipelines se documentan aquí. El proyecto
usa [Semantic Versioning](https://semver.org/).

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
