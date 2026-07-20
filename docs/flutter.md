# Contrato Flutter

## Runner

El pipeline acepta dos proveedores mediante el input `runner`:

```yaml
with:
  technology: flutter
  runner: github-hosted # o self-hosted
```

`self-hosted` es el valor predeterminado y utiliza estas labels:

```text
self-hosted, macOS, ARM64
```

Se pueden cambiar mediante el input JSON `runner-labels` del caller; este input
solo se usa cuando `runner` es `self-hosted`.
`github-hosted` asigna `macos-latest` a iOS y App Store, y `ubuntu-latest` a
validación, checks, Android, Web y Google Play. No requiere registrar un runner
y consume los minutos de GitHub Actions disponibles para el repositorio.

El Mac mini self-hosted debe tener Xcode, CocoaPods, Ruby/Bundler, Java y Android
SDK. Los workflows instalan la versión solicitada de Flutter y, en los jobs de
iOS, seleccionan una versión de Xcode que ya esté instalada en `/Applications`;
no descargan Xcode ni administran las credenciales del host. En GitHub-hosted se
debe usar una `XCODE_VERSION` incluida en la imagen `macos-latest`, o dejar el
valor `default`.

## Versiones de Flutter y Xcode

Las versiones se configuran en **Settings → Secrets and variables → Actions →
Variables** de cada repositorio consumidor:

```text
FLUTTER_VERSION=3.32.8
XCODE_VERSION=16.4
```

Son variables y no secrets porque las versiones no son información sensible.
El pipeline reutilizable lee las variables del repositorio que lo llama; no se
declaran `flutter-version` ni `xcode-version` en el YAML del caller.

Si una variable no existe, los defaults son `stable` para Flutter y `default`
para Xcode. `default` conserva el Xcode activo del runner; `XCODE_VERSION` debe
coincidir con la primera línea de `xcodebuild -version` y estar instalada bajo
`/Applications/Xcode*.app`.
La selección usa `DEVELOPER_DIR` únicamente durante el job, por lo que no cambia
el Xcode global del Mac y no requiere `sudo`.

No se recomienda guardar estas versiones como secrets: se ocultan en los logs,
no aportan seguridad y complican el diagnóstico. Los secrets se reservan para
firma, App Store Connect, Match y Google Play.

En repositorios pertenecientes a una cuenta personal, un runner de repositorio
solo procesa jobs de ese repositorio. El reusable workflow toma los runners del
contexto de la app que lo llama; no utiliza los runners registrados únicamente
en el repositorio central `workflows`.

## iOS (Fastlane)

El proyecto consumidor conserva la lógica específica de firma y publicación.
El workflow ejecuta:

```bash
bundle exec fastlane ios beta
bundle exec fastlane ios release
```

Las lanes reciben los secretos del environment de GitHub como variables de
entorno. Se recomiendan credenciales mediante App Store Connect API Key y Match,
nunca certificados guardados en este repositorio.

### Firma del draft con Match

El job iOS sincroniza certificados y perfiles con Fastlane Match antes de
ejecutar `flutter build ipa --release`. Match funciona en modo `readonly`, usa
el `fastlane/Matchfile` de la aplicación y crea mediante `setup_ci` un Keychain
temporal. El Keychain se elimina siempre al terminar y también se retiran los
perfiles que no estaban instalados antes del job. Esto funciona igual en
`self-hosted` y `github-hosted`.

Cada aplicación debe incluir `fastlane` en un `Gemfile` versionado junto con su
`Gemfile.lock`:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

El repositorio privado de Match se configura localmente una sola vez:

```bash
bundle install
bundle exec fastlane match init
bundle exec fastlane match appstore
```

El `fastlane/Matchfile` queda dentro de la aplicación y puede cubrir el target
principal y extensiones mediante varios bundle identifiers:

```ruby
git_url("https://github.com/TU_USUARIO/ios-signing.git")
git_branch("main")
storage_mode("git")
app_identifier([
  "com.tuempresa.tuapp",
  "com.tuempresa.tuapp.NotificationService",
])
```

La aplicación necesita estos **Repository Secrets**, porque la firma sucede en
el stage draft antes de entrar a los environments `beta` o `production`:

```text
MATCH_PASSWORD
MATCH_GIT_BASIC_AUTHORIZATION
```

`MATCH_PASSWORD` es la contraseña que cifra el repositorio de Match.
`MATCH_GIT_BASIC_AUTHORIZATION` contiene la autorización Basic en base64 para
un usuario o token con acceso de solo lectura al repositorio de firma. Se puede
generar sin salto de línea con:

```bash
printf '%s' 'USUARIO:TOKEN_READ_ONLY' | base64
```

Si ambos secrets están ausentes, el pipeline conserva el comportamiento
anterior y usa los certificados/perfiles ya instalados en el runner. Si solo
uno está configurado, el job falla antes de compilar para evitar una firma
parcial. No se deben guardar `.p12`, `.cer` o `.mobileprovision` dentro del
repositorio de la aplicación ni del repositorio central de workflows.

El draft ya produce el IPA firmado. `ios beta` recibe su ruta absoluta en
`IPA_PATH` y debe limitarse a subir ese archivo, por ejemplo con
`upload_to_testflight(ipa: ENV.fetch("IPA_PATH"))`; no debe ejecutar
`build_app` ni volver a firmar. También recibe `APP_VERSION` y `BUILD_NUMBER`.
`ios release` debe localizar ese mismo build beta y enviarlo o promoverlo a App
Store según la política del equipo.

## Android (Gradle Play Publisher)

La firma Android se configura con cuatro Repository Secrets en cada aplicación:

```text
ANDROID_KEYSTORE_BASE64
KEYALIAS
STOREPASSWORD
KEYPASSWORD
```

`ANDROID_KEYSTORE_BASE64` contiene el keystore completo codificado en base64,
no una ruta. Antes de compilar, el pipeline lo decodifica en
`RUNNER_TEMP`, valida el store password y el alias, y crea temporalmente
`android/key.properties` con la ruta real. Ambos archivos se eliminan siempre
al terminar el job. La aplicación debe ignorar `android/key.properties`,
`*.jks` y `*.keystore`; no debe guardar placeholders de secrets en esos
archivos.

El app bundle firmado se construye únicamente en draft. La fase beta descarga
ese AAB y ejecuta por defecto:

```bash
./gradlew publishBundle --track internal --artifact-dir "${AAB_ARTIFACT_DIRECTORY}"
```

`AAB_PATH` contiene la ruta absoluta del archivo y
`AAB_ARTIFACT_DIRECTORY` su directorio. El argumento `--artifact-dir` evita que
Gradle Play Publisher vuelva a construir o firmar el bundle.

La promoción ejecuta:

```bash
./gradlew promoteArtifact --from-track internal --promote-track production
```

La app debe configurar el plugin Gradle Play Publisher y proporcionar su
service account mediante los secretos del environment. Ambos comandos son
inputs del reusable workflow, por lo que pueden adaptarse a `closed`, `beta` u
otro esquema de tracks sin duplicar el pipeline.

## Secrets y environments

El template usa `secrets: inherit`: los secretos permanecen en el repo de cada
app y no pasan a este repositorio central. Los secrets de Match son Repository
Secrets porque se consumen durante draft. Configure las credenciales de subida
que consuman Fastlane y Gradle dentro de los environments `beta` y
`production`. Proteja `production` con reviewers si se requiere aprobación
humana.

## Versionado

La fuente única de versión de cada app es `pubspec.yaml`, usando obligatoriamente
el formato Flutter con build number numérico:

```yaml
version: 2.3.0+47
```

El pipeline expone a Fastlane y Gradle:

```text
APP_VERSION=2.3.0
BUILD_NUMBER=47
FULL_VERSION=2.3.0+47
```

Flutter usa esos mismos valores al construir. Los artefactos draft incluyen la
versión completa en el nombre. Las lanes/tareas no deben generar otra versión;
deben usar estas variables y asegurar que el build number no haya sido publicado
antes. Una promoción no recompila: promueve el binario que ya pasó por beta.

Este número es independiente de la versión mayor del pipeline central (`@v2`). La
primera versiona la aplicación; la segunda versiona las reglas de CI/CD.
