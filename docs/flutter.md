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
`github-hosted` asigna `macos-latest` a iOS, macOS y App Store, y
`ubuntu-latest` a validación, checks, Android, Web y Google Play. No requiere
registrar un runner y consume los minutos de GitHub Actions disponibles para el repositorio.

En Android, `github-hosted` instala el JDK remoto con `actions/setup-java` y
fuerza a Gradle a usar su `JAVA_HOME`. Esto tiene precedencia sobre un
`org.gradle.java.home` versionado con una ruta local de macOS. En
`self-hosted`, el workflow no instala ni reemplaza Java y conserva el JDK del
host.

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
JAVA_VERSION=17
XCODE_VERSION=16.4
```

Son variables y no secrets porque las versiones no son información sensible.
El pipeline reutilizable lee las variables del repositorio que lo llama; no se
declaran `flutter-version`, `java-version` ni `xcode-version` en el YAML del
caller. `JAVA_VERSION` solo se usa para el build Android en GitHub Hosted.

Si una variable no existe, los defaults son `stable` para Flutter, `17` para
Java y `default` para Xcode. `default` conserva el Xcode activo del runner;
`XCODE_VERSION` debe coincidir con la primera línea de `xcodebuild -version` y
estar instalada bajo `/Applications/Xcode*.app`.
La selección usa `DEVELOPER_DIR` únicamente durante el job, por lo que no cambia
el Xcode global del Mac y no requiere `sudo`.

No se recomienda guardar estas versiones como secrets: se ocultan en los logs,
no aportan seguridad y complican el diagnóstico. Los secrets se reservan para
firma, App Store Connect, Match y Google Play.

En repositorios pertenecientes a una cuenta personal, un runner de repositorio
solo procesa jobs de ese repositorio. El reusable workflow toma los runners del
contexto de la app que lo llama; no utiliza los runners registrados únicamente
en el repositorio central `workflows`.

## macOS nativo (Fastlane / App Store Connect)

El target Flutter `macos` se autodetecta si existe el directorio `macos/` y
también se puede pedir explícitamente con `platforms: android,ios,macos`. La
publicación requiere además `release-macos: true`; permanece desactivada por
defecto porque depende de una lane y firma Mac configuradas por el consumidor. El
job CI compila `flutter build macos --release` y conserva el `.app` como
artefacto de GitHub para inspección. Ese artefacto no se sube a Firebase y por sí
solo no es un paquete listo para Mac App Store.

Caller de ejemplo:

```yaml
with:
  technology: flutter
  platforms: android,ios,macos
  release-macos: true
```

La distribución de la app nativa para Mac se hace en la ruta Apple: TestFlight
para beta y promoción a Mac App Store en producción. El selector `platforms`
controla tanto el build macOS de CI como esta ruta de release. El job reusable
ejecuta las lanes del consumidor `bundle exec fastlane mac beta` y
`bundle exec fastlane mac release` (configurables con los inputs
`macos-beta-command` y `macos-production-command` del workflow central). Firebase
App Distribution solo recibe builds Android o iOS; no añadir el target macOS a sus
IDs o matrices.

Las lanes `mac beta` y `mac release` pertenecen al proyecto consumidor. Deben
crear y firmar un paquete macOS compatible con App Store Connect, usar la API key
que reciben por entorno y cargar la versión/build/SHA recibidos como
`APP_VERSION`, `BUILD_NUMBER`, `FULL_VERSION` y `SOURCE_SHA`. Deben resolver la
firma Mac App Distribution y el paquete instalador requerido por el flujo del
consumidor; el workflow común no reutiliza Match iOS ni afirma que la firma iOS
cubra macOS. Para `production`, la lane `mac release` promueve el build procesado
por Apple a Mac App Store.

Se requieren los mismos secrets `APP_STORE_CONNECT_API_KEY_BASE64`,
`APP_STORE_CONNECT_ISSUER_ID` y `APP_STORE_CONNECT_KEY_ID` en los environments
que publiquen. La app necesita un registro de macOS válido en App Store Connect y
la configuración de sandbox/copyright exigida para Mac App Store.

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
en la configuración `Release` de ese target dentro del checkout temporal del
job de build. No pasa el profile como un build setting global, por lo que los
targets de CocoaPods conservan su configuración sin firma. Para
`match-type: appstore` usa
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

The application needs these **Repository Secrets** because signing happens in
artifact-mode CI builds and direct beta jobs. A direct **Ready for review** run
builds the source once inside the `beta` environment job:

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

In direct mode, the TestFlight job builds one signed IPA and uploads it without
leaving the job. `ios beta` receives the validated absolute local path in
`IPA_PATH` and must only upload that file, for example with
`upload_to_testflight(api_key: app_store_connect_key, ipa:
ENV.fetch("IPA_PATH"))`; no debe ejecutar `build_app` ni volver a firmar. También
recibe `APP_VERSION` y `BUILD_NUMBER`.
`ios release` debe localizar ese mismo build beta y enviarlo o promoverlo a App
Store según la política del equipo.

Artifact mode remains available for existing callers. It uploads the IPA during
build and downloads that exact artifact before invoking the same beta lane.

### iOS source provenance contract

Direct iOS jobs pass the exact PR head commit as `SOURCE_SHA` and fail before
Fastlane unless `IOS_SOURCE_PROVENANCE_SUPPORTED=true` is configured as a
Repository Variable. Set this attestation only after both consumer lanes enforce
the contract.

`ios beta` must look up the exact `APP_VERSION` and `BUILD_NUMBER`. If TestFlight
**What to Test** metadata already contains `Source SHA: <SOURCE_SHA>`, it must
return success without uploading again. Otherwise it must upload `IPA_PATH` and
attach that marker to an explicit `APP_STORE_LOCALE`:

```ruby
locale = ENV["APP_STORE_LOCALE"].to_s.strip
UI.user_error!("APP_STORE_LOCALE is required") if locale.empty?

upload_to_testflight(
  # Other required upload options...
  changelog: marker,
  localized_build_info: {
    locale => { whats_new: marker }
  },
  skip_waiting_for_build_processing: true
)
```

Do not use `changelog` alone or a default `localized_build_info` entry for this
contract. With `skip_waiting_for_build_processing`, Fastlane uses `changelog` as
the signal to wait only until the new build appears and then applies distribution
metadata. The explicit locale key lets that distribution step create the
`BetaBuildLocalization` and persist its `whatsNew` value. `ios release` must fetch
the same TestFlight build and fail unless its metadata contains that exact marker
before selecting or submitting it. Merely accepting `SOURCE_SHA` does not satisfy
the contract.

### Metadata de App Store

Los campos localizados requeridos por App Store Connect se configuran como
**Repository Variables** en la aplicación consumidora:

```text
APP_STORE_LOCALE=es-ES
APP_STORE_DESCRIPTION=Descripción completa de la aplicación.
APP_STORE_KEYWORDS=entrenamiento,bienestar,fitness
APP_STORE_SUPPORT_URL=https://example.com/soporte
APP_STORE_RELEASE_NOTES=Mejoras de rendimiento y correcciones de errores.
```

`APP_STORE_RELEASE_NOTES` corresponde exclusivamente al campo **What's New**
de la versión. Las cinco variables son obligatorias para una publicación a
producción; el workflow falla antes de invocar Fastlane si falta alguna.
`APP_STORE_KEYWORDS` debe contener palabras separadas por comas y
`APP_STORE_SUPPORT_URL` debe ser una URL pública completa.

El workflow expone esas variables a la lane `ios release` con los mismos
nombres y crea un directorio temporal compatible con `deliver` mediante
`DELIVER_METADATA_PATH`. Esto permite que lanes existentes que llaman
`upload_to_app_store` carguen los cuatro archivos localizados sin cambios. Aun
así, una implementación explícita recomendada es:

```ruby
locale = ENV["APP_STORE_LOCALE"].to_s.strip
description = ENV["APP_STORE_DESCRIPTION"].to_s.strip
keywords = ENV["APP_STORE_KEYWORDS"].to_s.strip
support_url = ENV["APP_STORE_SUPPORT_URL"].to_s.strip
release_notes = ENV["APP_STORE_RELEASE_NOTES"].to_s.strip

UI.user_error!("APP_STORE_LOCALE is required") if locale.empty?
UI.user_error!("APP_STORE_DESCRIPTION is required") if description.empty?
UI.user_error!("APP_STORE_KEYWORDS is required") if keywords.empty?
UI.user_error!("APP_STORE_SUPPORT_URL is required") if support_url.empty?
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

options[:description] = { locale => description }
options[:keywords] = { locale => keywords }
options[:support_url] = { locale => support_url }
options[:release_notes] = { locale => release_notes }

deliver(**options)
```

`deliver` es un alias de `upload_to_app_store`. Los hashes asocian cada valor
con `APP_STORE_LOCALE`; pasar solamente strings desde la CLI no permite expresar
correctamente metadata localizada, por eso esta configuración debe estar en la
lane del `Fastfile`.

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
`android/key.properties` con la ruta real. Si el módulo de aplicación referencia
explícitamente `keystore.properties`, conserva esa convención para aplicaciones
anteriores. Ambos archivos se eliminan siempre al terminar el job. La aplicación
debe ignorar `android/key.properties`, `android/keystore.properties`, `*.jks` y
`*.keystore`; no debe guardar placeholders de secrets en esos archivos.

Direct beta delivery forces `appbundle`, builds one signed AAB inside the
`beta` environment job, validates its exact local path and AGP package metadata,
then passes both values to
[`r0adkll/upload-google-play`](https://github.com/r0adkll/upload-google-play#inputs).
It does not use `actions/upload-artifact` or `actions/download-artifact`.

La aplicación puede declarar únicamente un track diferente al predeterminado:

```yaml
with:
  technology: flutter
  platforms: android,ios
  android-build-format: appbundle
  android-track: alpha
  android-flavor: ${{ vars.ANDROID_FLAVOR }}
```

`android-track` usa `alpha` por defecto como pista cerrada convencional, así que
también puede omitirse. Si la app usa otra pista cerrada creada en Play Console,
se debe configurar aquí su identificador exacto. `beta` identifica la pista de
pruebas abiertas y no debe usarse cuando la política exige pruebas cerradas.
`android-flavor` es opcional y queda vacío por defecto. El template lo lee de la
Repository Variable `ANDROID_FLAVOR`; configúrala si el proyecto Android declara
product flavors. El valor se pasa a los builds de artefactos y al build directo
de beta. La matriz `FIREBASE_ANDROID_DISTRIBUTIONS` elige independientemente el
flavor de cada distribución Firebase.

Direct beta uses a short-lived Android Publisher access token, uploads the exact
validated local `.aab`, and never writes the service-account JSON to disk.
`packageName` comes from Android Gradle Plugin metadata and must match
`APP_IDENTIFIER` when configured. Artifact mode continues to use the pinned
upload action with its existing inputs.

Direct production does not download, rebuild, or upload an AAB. It opens an
Android Publisher edit, selects the highest version code from completed releases
on `android-track`, and replaces the completed `production` release with only that
selected version code. It fails when the
closed-testing track has no completed release, when production contains an active
rollout, or when promotion would downgrade production. iOS production continues
through `ios release`, whose consumer lane must select and submit the latest
eligible processed TestFlight beta.

Artifact mode preserves the previous integration for external callers: it
downloads the signed AAB and uses the pinned upload action for beta or production.
Direct Android beta names the release with the exact source SHA and is idempotent
only when both version code and name match. Production selects by the latest
completed version code, removes older fully superseded production version codes,
and refuses to replace draft, halted, or staged rollouts.

### Firebase App Distribution por flavor

La distribución Android a Firebase se configura por aplicación mediante la
Repository Variable `FIREBASE_ANDROID_DISTRIBUTIONS`. Es una lista JSON con una
entrada por flavor; cada entrada elige el comando de build (`apk` o
`appbundle`) y el nombre del flavor de esa app:

```json
[
  {"flavor":"qa","format":"apk"},
  {"flavor":"preprod","format":"appbundle"}
]
```

Los nombres `qa` y `preprod` son ejemplos. El workflow central no conoce los
flavors de las compañías que lo consumen; cada repositorio define sus propios
valores. Cada entrada se compila usando `--flavor`. El pipeline obtiene el
package name de ese build y lo cruza con las apps Android registradas en el
proyecto de la cuenta de servicio para resolver el App ID correcto. Si las
variantes usan distintos proyectos Firebase, se puede añadir `project_id` a la
entrada correspondiente; la cuenta debe tener permisos en cada proyecto. Una
lista vacía (`[]`) omite esta distribución por flavor.

Configurar también estas variables y credenciales en el repositorio consumidor:

```text
FIREBASE_APP_DISTRIBUTION_GROUPS=qa-testers
FIREBASE_SERVICE_ACCOUNT_JSON=<service account JSON como Actions Secret>
```

`FIREBASE_SERVICE_ACCOUNT_JSON` debe guardarse como **Repository Secret**; la
plantilla lo pasa al job `cd`. El pipeline usa el `project_id` de esa cuenta y
el package name generado por el build para resolver automáticamente el App ID
entre las apps Android activas del proyecto. La lista no necesita guardar un
App ID por flavor. La cuenta requiere el rol **Firebase App Distribution
Admin**, que permite subir builds y listar las apps. Los grupos son comunes a
todas las entradas de la lista. Si se distribuye un AAB, Firebase requiere que
la app Android esté vinculada a una aplicación de Google Play. También deben
estar disponibles los secrets de firma Android usados por los builds.

La subida usa Firebase CLI con Application Default Credentials para funcionar
en los runners Linux y macOS admitidos por el pipeline; no requiere Docker.

Para mantener compatibilidad, si `FIREBASE_ANDROID_DISTRIBUTIONS` vale `[]` y
está configurada la variable antigua `FIREBASE_APP_ID_ANDROID`, se conserva la
distribución anterior del AAB beta sin selección de flavor.

Define one `FIREBASE_SERVICE_ACCOUNT_JSON` Repository Secret with the complete
service-account JSON. The same account is used for Firebase App Distribution
and Google Play, so grant it the required Firebase App Distribution and Play
Console permissions. Direct mode exchanges it for an in-memory, short-lived
access token without creating a credentials file.

## Secrets y environments

El template pasa cada secret por nombre. Esto mantiene el mínimo privilegio y
funciona aunque la app y el workflow central tengan owners diferentes, donde
`secrets: inherit` no está soportado. Los valores permanecen en el repositorio de
cada app; no se configuran en este repositorio central. Los secrets de Match son
Repository Secrets porque se consumen durante builds CI en modo `artifact` y
builds beta en modo `direct`. Configure
las credenciales de subida que consuman Fastlane y Google Play dentro de los
environments `beta` y `production`.

Direct mode requires reviewers on both environments because these jobs execute
consumer build and Fastlane code while signing and store credentials are in
scope. The supplied template defaults to ephemeral GitHub-hosted runners.
Explicit self-hosted callers accept the additional workspace isolation risk.
Artifact mode retains its pre-existing signed CI behavior for compatibility.

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

Flutter uses these same values while building. Artifact-mode build names include
the full version. Direct release lanes and tasks must not generate another
version. Android direct beta publishes `BUILD_NUMBER`; direct production instead
derives the latest completed version code from the configured closed-testing
track.

Este número es independiente de la versión mayor del workflow central (`@v4`). La
primera versiona la aplicación; la segunda versiona las reglas de CI/CD.
