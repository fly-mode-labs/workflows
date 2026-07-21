# Changelog

Todos los cambios relevantes de los pipelines se documentan aquí. El proyecto
usa [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- Validación de los workflows con `raven-actions/actionlint@v2` en cada PR y
  push a `main`.
- Creación automática de certificados y perfiles iOS ausentes en el repositorio
  privado de Match. Los builds primero intentan sincronizar en modo `readonly` y
  solo permiten escritura cuando falta la identidad o el provisioning profile
  de la aplicación.
- La publicación de App Store propaga las Repository Variables localizadas
  `APP_STORE_DESCRIPTION`, `APP_STORE_KEYWORDS`, `APP_STORE_SUPPORT_URL` y
  `APP_STORE_RELEASE_NOTES` a Fastlane, y valida los campos requeridos antes de
  ejecutar `deliver`. Las release notes se envían como el campo **What's New**.

### Changed

- Los runners GitHub-hosted delegan la selección de Xcode a
  `maxim-lobanov/setup-xcode@v1` y la preparación de Ruby, Bundler y la caché de
  gems a `ruby/setup-ruby@v1`. Los runners self-hosted conservan la selección
  aislada mediante `DEVELOPER_DIR` y el Ruby instalado en el Mac.
- Google Play beta descarga el AAB con `actions/download-artifact@v8` y lo publica
  directamente con `r0adkll/upload-google-play@v1.1.5`, usando los inputs documentados
  `serviceAccountJsonPlainText`, `packageName`, `releaseFiles`, `tracks` y
  `status`.
- La distribución Android beta ya no hace checkout, instala Flutter, configura
  el proyecto Android ni ejecuta Gradle. El application ID efectivo se extrae
  del metadata generado por Android Gradle Plugin y se transporta junto al AAB;
  la Repository Variable `APP_IDENTIFIER` se usa para comprobar que el destino
  de Google Play coincide con el artefacto firmado. `android-track` permite
  seleccionar el track y usa `internal` de forma predeterminada.
- Los artefactos Android usan `actions/upload-artifact@v7` con compresión `0`,
  apropiada para AAB/APK ya comprimidos y documentada por la acción upstream.

### Fixed

- Las referencias internas a composite actions usan ahora el tag completo e
  inmutable `v3.4.11`. Esto cambia la clave de caché de los runners self-hosted
  y evita que el alias móvil `v3` reutilice una implementación anterior de la
  acción, como la que ejecutaba `promoteArtifact` sin aplicar el plugin.
- La firma Android detecta si el módulo Gradle consume `key.properties` o la
  convención anterior `keystore.properties`. Esto evita crear el archivo con un
  nombre que la aplicación no lee y que `signReleaseBundle` falle después con
  una configuración de firma nula.
- La promoción Android inyecta temporalmente Gradle Play Publisher `3.13.0` en
  el módulo de aplicación cuando el proyecto no lo declara. `promoteArtifact`
  queda disponible con Gradle 8.11.1 y el archivo de build original se restaura
  al terminar.
- Los workflows reutilizables de `v3` ya no retroceden internamente a acciones
  y workflows de `v2`. La promoción de App Store ejecuta ahora la acción iOS de
  la misma versión mayor, que propaga `description`, `keywords`, `supportUrl` y
  `whatsNew`; las llamadas entre workflows usan el mismo commit del caller para
  evitar divergencias futuras.
- La acción de producción iOS materializa las Repository Variables como
  metadata localizada temporal de `deliver`. Esto mantiene compatibles las
  lanes existentes que todavía no convierten esas variables en hashes Ruby.
- Cuando un runner self-hosted tiene menos de 5 GiB libres, el build Android
  elimina primero las cachés regenerables de Gradle y conserva los módulos y
  las distribuciones descargadas. El workflow invoca la versión `v3` de la
  acción que contiene esta limpieza y vuelve a medir el espacio después de
  eliminar una caché de proyecto anterior. La limpieza final calcula su propia
  ruta de caché y ya no falla si la preparación termina antes de exportar el
  entorno.
- La publicación beta iniciada al marcar una PR como **Ready for review** espera
  hasta 40 minutos cuando el build draft del mismo commit todavía está en cola o
  en ejecución. Esto evita que los builds más lentos de GitHub Hosted fallen de
  inmediato indicando que no existen artefactos. El resolvedor usa además
  `actions/github-script@v8`, compatible de forma nativa con Node.js 24.
- El pipeline central invoca el workflow de build Flutter desde el mismo commit,
  evitando que `main.yml@v3` valide el input `java-version` contra la interfaz
  anterior de `flutter-build.yml@v2`.
- Los builds Android en GitHub Hosted instalan el JDK remoto configurado por
  `JAVA_VERSION` (17 por defecto) y lo seleccionan explícitamente para Gradle,
  evitando fallos cuando la app conserva un `org.gradle.java.home` con una ruta
  absoluta del runner self-hosted.
- La publicación Android valida `APP_IDENTIFIER` antes de invocar Google
  Play y muestra una instrucción explícita si la Repository Variable falta o no
  contiene un application ID válido.
- El composite Android consume `APP_IDENTIFIER` mediante su input `identifier`,
  ya que el contexto `vars` no está disponible al validar el manifiesto de una
  composite action. El workflow exterior resuelve la Repository Variable y la
  propaga explícitamente a través de los workflows anidados. Los runs iniciados
  con una revisión anterior de `v2` que no propaga ese input conservan
  compatibilidad mediante el application ID incluido en el artefacto Android.
- Los artefactos Android vuelven a incluir `android-package-name.txt`; la
  publicación usa ese valor como fuente de verdad y detecta diferencias con
  `APP_IDENTIFIER` antes de invocar Google Play.
- El provisioning profile de Match se aplica únicamente al target `Runner` en
  Release; ya no se propaga a los targets de CocoaPods que no admiten firma.
- Los builds iOS con Match ya no delegan la firma automática a Xcode. El
  pipeline resuelve el provisioning profile del target `Runner`, firma los
  archives App Store con `Apple Distribution` y genera opciones de exportación
  manuales, evitando solicitudes de login y certificados de desarrollo.
- Cuando un runner self-hosted no tiene espacio suficiente para Android, el
  build elimina la copia antigua de Flutter que quedó sin uso en
  `RUNNER_TOOL_CACHE` después de migrar el SDK a `runner.temp`. La copia activa
  indicada por `FLUTTER_ROOT` nunca se elimina.

## [2.3.6] - 2026-07-20

### Fixed

- La publicación del pipeline usa `ubuntu-latest` porque solo necesita Git y
  GitHub CLI; ya no queda bloqueada esperando un runner self-hosted dedicado.
- Los releases se serializan y una versión nueva cancela una publicación
  anterior todavía en curso, evitando que el alias mayor retroceda.

## [2.3.5] - 2026-07-20

### Fixed

- La validación del setup obtiene `frameworkVersion` desde la salida JSON de
  `flutter --version --machine`, sin depender de mensajes destinados a humanos.
- Una prueba de regresión reproduce el aviso de actualización observado en los
  runners self-hosted y se ejecuta en cada PR, push a `main` y publicación.

## [2.3.4] - 2026-07-20

### Fixed

- La validación del setup de Flutter obtiene la versión desde la línea que
  comienza con `Flutter <versión>`, evitando interpretar como versión la palabra
  `is` del aviso de actualización mostrado por el SDK.

## [2.3.3] - 2026-07-19

### Fixed

- El setup de Flutter instala el SDK bajo `runner.temp` para evitar reutilizar
  instalaciones incompletas persistidas en `RUNNER_TOOL_CACHE` por runners
  self-hosted, manteniendo la restauración mediante `actions/cache`.
- El setup valida `FLUTTER_ROOT` y el repositorio Git del SDK antes de ejecutar
  comandos de Flutter, produciendo un diagnóstico explícito si la instalación
  está incompleta.

## [2.3.1] - 2026-07-19

### Fixed

- Las PR creadas o reabiertas directamente como open ahora ejecutan beta sin
  exigir una transición previa desde draft.
- La distribución iOS ahora propaga y valida explícitamente
  `APP_STORE_CONNECT_API_KEY_BASE64`, `APP_STORE_CONNECT_ISSUER_ID` y
  `APP_STORE_CONNECT_KEY_ID` antes de invocar Fastlane.

## [2.3.0] - 2026-07-19

### Changed

- Beta ya no requiere una ejecución draft previa: primero corre checks y
  compila los artefactos firmados del commit actual, y después los distribuye
  desde la misma ejecución.
- `flutter-release.yml` acepta `artifact-run-id` para consumir explícitamente
  los artefactos generados por el orquestador, conservando como fallback la
  resolución de un build exitoso anterior.

## [2.2.0] - 2026-07-19

### Added

- Firma iOS opcional con Fastlane Match en modo `readonly`, usando `setup_ci`
  para instalar certificados y perfiles en un Keychain temporal tanto en
  runners self-hosted como GitHub-hosted.
- Limpieza del Keychain temporal y de los perfiles de aprovisionamiento
  agregados durante el job.

### Changed

- Una configuración parcial de Match falla antes del build; cuando ambos
  secrets de Match están ausentes se conserva la firma instalada en el runner.
- La distribución de iOS y Android vive en composite actions independientes,
  `release-ios` y `release-android`; los workflows de App Store y Google Play
  quedan limitados a orquestar cada job de CD.

## [2.1.0] - 2026-07-19

### Changed

- Checks, Android, iOS y Web son jobs explícitos e independientes, agrupados
  bajo el prefijo `Flutter build /`; se ejecutan en paralelo y cada uno admite
  un re-run individual.
- Los artefactos de build pueden reemplazarse durante un re-run del mismo job.

## [2.0.0] - 2026-07-19

### Added

- La distribución beta exige un run draft exitoso del mismo commit y reutiliza
  sus artefactos Android/iOS entre ejecuciones de GitHub Actions.

### Changed

- TestFlight recibe el IPA firmado mediante `IPA_PATH`, sin volver a compilar
  la aplicación.
- Google Play publica el AAB firmado descargado mediante
  `publishBundle --artifact-dir`, sin volver a construirlo ni recrear la firma.

### Migration

- Los callers deben cambiar de `@v1` a `@v2` y conceder `actions: read`.
- La lane `ios beta` debe subir el archivo indicado por `IPA_PATH` y no ejecutar
  un build nuevo.

## [1.3.0] - 2026-07-19

### Added

- Input `runner` para elegir entre el Mac mini `self-hosted` y runners
  `github-hosted`, incluido como selector en las ejecuciones manuales del
  template Flutter. GitHub Actions asigna `macos-latest` a iOS/App Store y
  `ubuntu-latest` a validación, checks, Android, Web y Google Play.

## [1.2.0] - 2026-07-19

### Added

- Configuración de `FLUTTER_VERSION` y `XCODE_VERSION` mediante Repository
  variables del repositorio consumidor, y selección aislada de Xcode mediante
  `DEVELOPER_DIR`.

### Fixed

- Los builds Android usan una caché de proyecto Gradle aislada por ejecución,
  desactivan el daemon persistente y fallan con un diagnóstico claro cuando el
  runner tiene menos de 5 GiB libres, evitando reutilizar locks de builds
  cancelados o incompletos.
- El setup muestra y valida la versión efectiva de Flutter leída desde la
  variable `FLUTTER_VERSION` del repositorio consumidor.
- La firma Android ahora consume explícitamente
  `ANDROID_KEYSTORE_BASE64`, `KEYALIAS`, `STOREPASSWORD` y `KEYPASSWORD`,
  decodifica y valida el keystore antes del build y elimina los archivos
  temporales al finalizar.
- Los checks de Flutter se ejecutan desde el directorio de la aplicación y el
  análisis queda limitado a `lib`, `test` e `integration_test`, evitando
  analizar dependencias descargadas dentro de `build/ios/SourcePackages`.
- El build draft de iOS conserva la firma configurada por la aplicación y ya no
  fuerza `--no-codesign`.
- La versión de Flutter también se propaga al flujo de producción.

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
