# Contrato Flutter

## Runner

El runner debe tener Flutter, Xcode, CocoaPods, Ruby/Bundler, Java y Android SDK.
Los workflows instalan la versión solicitada de Flutter, pero no administran
Xcode ni las credenciales del host. Labels predeterminadas:

```text
self-hosted, macOS, ARM64
```

Se pueden cambiar mediante el input JSON `runner-labels` del caller.

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

`ios beta` debe incrementar/resolver el build number, firmar y subir a
TestFlight. `ios release` debe localizar el build beta aprobado y enviarlo o
promoverlo a App Store según la política del equipo.

## Android (Gradle Play Publisher)

La fase beta construye el app bundle y ejecuta por defecto:

```bash
./gradlew publishBundle --track internal
```

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
app y no pasan a este repositorio central. Configure al menos lo que consuman
Fastlane y Gradle en los environments `beta` y `production`. Proteja
`production` con reviewers si se requiere aprobación humana.

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

Este número es independiente de la versión del pipeline central (`@v1.0.0`). La
primera versiona la aplicación; la segunda versiona las reglas de CI/CD.
