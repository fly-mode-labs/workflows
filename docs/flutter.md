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

La publicación exige estos tres secrets, usando exactamente los mismos nombres
en los environments `beta` y `production` (o como Repository Secrets si ambos
environments compartirán la credencial):

```text
APP_STORE_CONNECT_API_KEY_BASE64
APP_STORE_CONNECT_ISSUER_ID
APP_STORE_CONNECT_KEY_ID
```

El primero contiene el archivo privado `.p8` completo codificado en base64. El
pipeline pasa los tres valores sin renombrarlos a `ios beta` e `ios release`.
El `Fastfile` de la aplicación puede construir una única credencial reutilizable:

```ruby
def app_store_connect_key
  app_store_connect_api_key(
    key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
    issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
    key_content: ENV.fetch("APP_STORE_CONNECT_API_KEY_BASE64"),
    is_key_content_base64: true
  )
end
```

### Firma del build con Match

El job iOS sincroniza certificados y perfiles con Fastlane Match antes de
ejecutar `flutter build ipa --release`. Match funciona en modo `readonly`, usa
el `fastlane/Matchfile` de la aplicación y crea mediante `setup_ci` un Keychain
temporal. El Keychain se elimina siempre al terminar y también se retiran los
perfiles que no estaban instalados antes del job. Esto funciona igual en
`self-hosted` y `github-hosted`.

Cuando Match está configurado, el pipeline lee el provisioning profile que
instaló para el bundle identifier del target `Runner` y fuerza la firma manual
en la configuración `Release` de ese target dentro del checkout temporal de
CI. No pasa el profile como un build setting global, por lo que los targets de
CocoaPods conservan su configuración sin firma. Para `match-type: appstore` usa
`Apple Distribution`, el team del profile y su nombre exacto tanto en el
archive como en `ExportOptions.plist`. De esta forma Xcode no intenta iniciar
sesión con una cuenta de Apple ni busca un certificado `iOS Development`. El
proyecto puede conservar firma automática para desarrollo local; no es
necesario versionar un `.p12` ni modificar `project.pbxproj` para el runner.

La resolución automática actual cubre el target Flutter principal `Runner`.
Una aplicación con extensiones firmadas necesita configurar sus targets y el
mapa `provisioningProfiles` de forma específica para cada bundle identifier.

Cada aplicación debe incluir `fastlane` en un `Gemfile` versionado junto con su
`Gemfile.lock`:

```ruby
source "https://rubygems.org"

gem "fastlane"
```

El primer build intenta descargar las credenciales en modo `readonly`. Si el
repositorio privado de Match todavía no contiene la identidad o el provisioning
profile requerido por la aplicación, el pipeline ejecuta automáticamente la lane
`ios sync_signing` con `readonly: false`, crea los recursos ausentes y los guarda
cifrados. Para crear esos recursos, `MATCH_GIT_BASIC_AUTHORIZATION` debe usar un
token con acceso de escritura y las tres credenciales de App Store Connect deben
ser Repository Secrets.

También se puede configurar e inicializar previamente de forma local:

```bash
bundle install
bundle exec fastlane match init
bundle exec fastlane ios sync_signing
```

La lane local que crea y sube por primera vez los certificados y perfiles al
repositorio privado de Match puede reutilizar la misma API key:

```ruby
platform :ios do
  lane :sync_signing do
    match(type: "appstore", readonly: false, api_key: app_store_connect_key)
  end
end
```

Antes de ejecutarla, esas tres variables y `MATCH_PASSWORD` deben existir en la
terminal local. GitHub no permite volver a leer el valor de un secret ya
guardado. Match genera o descarga los recursos, los cifra y hace commit/push al
repositorio configurado; no se copian `.p12` o `.mobileprovision` manualmente.

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
los jobs de build antes de publicar; **Ready for review** reutiliza el build
firmado del draft del mismo commit:

```text
MATCH_PASSWORD
MATCH_GIT_BASIC_AUTHORIZATION
```

`MATCH_PASSWORD` es la contraseña que cifra el repositorio de Match.
`MATCH_GIT_BASIC_AUTHORIZATION` contiene la autorización Basic en base64 para
un usuario o token con acceso al repositorio de firma. La inicialización
automática necesita escritura para crear el primer commit; después puede
reemplazarse por un token de solo lectura para los builds habituales. Se puede
generar sin salto de línea con:

```bash
printf '%s' 'USUARIO:TOKEN' | base64
```

Si ambos secrets están ausentes, el pipeline conserva el comportamiento
anterior y usa los certificados/perfiles ya instalados en el runner. Si solo
uno está configurado, el job falla antes de compilar para evitar una firma
parcial. No se deben guardar `.p12`, `.cer` o `.mobileprovision` dentro del
repositorio de la aplicación ni del repositorio central de workflows.

El build previo produce el IPA firmado. En **Ready for review** se reutiliza el
artefacto del draft del mismo commit; una beta manual o una PR creada directamente
como open puede producirlo en su propia ejecución. `ios beta` recibe su ruta
absoluta en `IPA_PATH` y debe limitarse a subir ese archivo, por ejemplo con
`upload_to_testflight(api_key: app_store_connect_key, ipa:
ENV.fetch("IPA_PATH"))`; no debe ejecutar `build_app` ni volver a firmar. También
recibe `APP_VERSION` y `BUILD_NUMBER`.
`ios release` debe localizar ese mismo build beta y enviarlo o promoverlo a App
Store según la política del equipo.

### Metadata de App Store

La metadata estable y localizada (descripción, keywords, URLs, subtítulo y
texto promocional) debe vivir versionada en `fastlane/metadata`. Las notas que
cambian para cada publicación se configuran como **Repository Variables** en la
aplicación consumidora:

```text
APP_STORE_LOCALE=es-ES
APP_STORE_RELEASE_NOTES=Mejoras de rendimiento y correcciones de errores.
```

`APP_STORE_RELEASE_NOTES` corresponde exclusivamente al campo **What's New**
de la versión. Es opcional para el workflow reutilizable; las lanes de las apps
pueden exigirla para impedir una promoción sin notas.

El workflow expone esas variables a la lane `ios release` con los mismos
nombres. Una implementación recomendada es:

```ruby
locale = ENV["APP_STORE_LOCALE"].to_s.strip
release_notes = ENV["APP_STORE_RELEASE_NOTES"].to_s.strip

UI.user_error!("APP_STORE_LOCALE is required") if locale.empty?
UI.user_error!("APP_STORE_RELEASE_NOTES is required") if release_notes.empty?

options = {
  api_key: app_store_connect_key,
  app_identifier: APP_IDENTIFIER,
  app_version: ENV.fetch("APP_VERSION"),
  build_number: ENV.fetch("BUILD_NUMBER"),
  skip_binary_upload: true,
  skip_metadata: false,
  skip_screenshots: true,
  submit_for_review: true,
  automatic_release: true,
  force: true,
  # La API Key todavía no permite a precheck consultar las compras integradas.
  precheck_include_in_app_purchases: false
}

options[:release_notes] = { locale => release_notes }

upload_to_app_store(**options)
```

No se recomienda `run_precheck_before_submit: false`: desactivaría todas las
comprobaciones. `precheck_include_in_app_purchases: false` omite solamente la
consulta que no es compatible con App Store Connect API Key y conserva el resto
de la validación.

## Android (Google Play)

La firma Android se configura con cuatro Repository Secrets en cada aplicación:

```text
ANDROID_KEYSTORE_BASE64
KEYALIAS
STOREPASSWORD
KEYPASSWORD
```

El application ID usado para publicar en Google Play se configura como
Repository Variable en la misma sección de Actions:

```text
APP_IDENTIFIER=com.example.app
```

Debe coincidir exactamente con el `applicationId` del AAB firmado. No es un
secret y no se declara como input en el workflow caller.

`ANDROID_KEYSTORE_BASE64` contiene el keystore completo codificado en base64,
no una ruta. Antes de compilar, el pipeline lo decodifica en
`RUNNER_TEMP`, valida el store password y el alias, y crea temporalmente
`android/key.properties` con la ruta real. Ambos archivos se eliminan siempre
al terminar el job. La aplicación debe ignorar `android/key.properties`,
`*.jks` y `*.keystore`; no debe guardar placeholders de secrets en esos
archivos.

El app bundle firmado se construye en el build previo. En **Ready for review** se
reutiliza el artefacto del draft del mismo commit; los otros disparadores beta
pueden producirlo en su propia ejecución. La fase de distribución usa
[`actions/download-artifact`](https://github.com/actions/download-artifact#usage)
para descargar el AAB y
[`r0adkll/upload-google-play`](https://github.com/r0adkll/upload-google-play#inputs)
para enviarlo directamente a Google Play mediante la Android Publisher API.

La aplicación puede declarar únicamente un track diferente al predeterminado:

```yaml
with:
  technology: flutter
  platforms: android,ios
  android-build-format: appbundle
  android-track: internal
```

`android-track` usa `internal` por defecto, así que también puede omitirse. Se
puede cambiar a `beta` o a un track personalizado existente en Play Console.

La acción recibe exactamente los inputs documentados por su autor:
`serviceAccountJsonPlainText`, `packageName`, `releaseFiles`, `tracks` y
`status`. `packageName` recibe el application ID extraído por Android Gradle
Plugin durante el build; si `APP_IDENTIFIER` está disponible, el pipeline exige
que ambos valores coincidan. `releaseFiles` usa el glob soportado oficialmente
para seleccionar el único `.aab` dentro del artefacto descargado. La
distribución beta no hace checkout, no instala Flutter y no ejecuta Gradle,
Android SDK ni NDK. Tampoco recompila ni vuelve a firmar el AAB.

La promoción ejecuta:

```bash
./gradlew promoteArtifact --from-track internal --promote-track production
```

La promoción a producción conserva temporalmente Gradle Play Publisher porque
`upload-google-play` no documenta una operación de promoción sin volver a subir
el artefacto. Solo para esa etapa la app debe aplicar el plugin en el módulo
Android de aplicación, usando una versión compatible con su Gradle/AGP:

```groovy
plugins {
    id 'com.github.triplet.play' version '4.0.0'
}
```

Cada environment de GitHub (`beta` y `production`) debe definir
`ANDROID_PUBLISHER_CREDENTIALS` con el contenido completo del JSON de la cuenta
de servicio. En beta se entrega al input `serviceAccountJsonPlainText` de la
acción; en producción se expone a Gradle Play Publisher con su nombre estándar.

## Secrets y environments

El template usa `secrets: inherit`: los secretos permanecen en el repo de cada
app y no pasan a este repositorio central. Los secrets de Match son Repository
Secrets porque se consumen durante los builds draft y beta. Configure las
credenciales de subida que consuman Fastlane y Google Play dentro de los
environments `beta` y `production`. Proteja `production` con reviewers si se requiere
aprobación humana.

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

Flutter usa esos mismos valores al construir. Los artefactos de build incluyen
la versión completa en el nombre. Las lanes/tareas no deben generar otra versión;
deben usar estas variables y asegurar que el build number no haya sido publicado
antes. Una promoción no recompila: promueve el binario que ya pasó por beta.

Este número es independiente de la versión mayor del pipeline central (`@v2`). La
primera versiona la aplicación; la segunda versiona las reglas de CI/CD.
