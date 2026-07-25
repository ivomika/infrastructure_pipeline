# Flutter Jenkins agent

The `flutter` agent contains Flutter, Dart, Android SDK, JDK 21, Git, and the
archive utilities used by the shared library.

Use it with:

```groovy
agent { label 'flutter' }
```

## Typical Android and web pipeline

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'flutter' }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Toolchain') {
      steps {
        flutterDoctor()
      }
    }

    stage('Dependencies') {
      steps {
        flutterPubGet()
      }
    }

    stage('Quality') {
      parallel {
        stage('Analyze') {
          steps {
            flutterAnalyze()
          }
        }
        stage('Tests') {
          steps {
            flutterTest(COVERAGE: true)
          }
        }
      }
    }

    stage('Build') {
      steps {
        buildApk(BUILD_MODE: 'release')
        buildAppBundle(BUILD_MODE: 'release')
        buildWeb()
      }
    }

    stage('Archive') {
      steps {
        archiveBuildArtifacts(
          ITEMS: [
            [
              SOURCE: 'build/app/outputs/flutter-apk/app-release.apk',
              NAME: "app-${env.BUILD_NUMBER}.apk"
            ],
            [
              SOURCE: 'build/app/outputs/bundle/release/app-release.aab',
              NAME: "app-${env.BUILD_NUMBER}.aab"
            ],
            [
              SOURCE: 'build/web',
              NAME: "web-${env.BUILD_NUMBER}.zip",
              FORMAT: 'zip'
            ]
          ]
        )
      }
    }
  }

  post {
    always {
      junit allowEmptyResults: true, testResults: 'build/**/test-results/**/*.xml'
    }
  }
}
```

For a monorepo, pass `PROJECT_DIR: 'path/to/app'` to the shared-library steps.
