# Java Jenkins agent

The `java` agent contains JDK 21, Maven, Git, and utilities required by Maven
Wrapper and Gradle Wrapper. It is available through the `java`, `maven`, and
`backend` labels.

Use it with:

```groovy
agent { label 'java' }
```

## Typical Maven pipeline

`mavenBuild()` uses `mvnw` when it exists and falls back to the installed Maven.
Its default goals are `clean verify`.

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'java' }

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

    stage('Build and test') {
      steps {
        mavenBuild()
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/target/surefire-reports/*.xml'
        }
      }
    }

    stage('Archive') {
      steps {
        archiveArtifacts artifacts: '**/target/*.jar', fingerprint: true
      }
    }
  }
}
```

## Typical Gradle pipeline

The repository must contain Gradle Wrapper. The default tasks are
`clean build`.

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'java' }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build and test') {
      steps {
        gradleBuild()
      }
      post {
        always {
          junit allowEmptyResults: true, testResults: '**/build/test-results/test/*.xml'
        }
      }
    }

    stage('Archive') {
      steps {
        archiveArtifacts artifacts: '**/build/libs/*.jar', fingerprint: true
      }
    }
  }
}
```

For a monorepo, use `mavenBuild(PROJECT_DIR: 'services/api')` or
`gradleBuild(PROJECT_DIR: 'services/api')`.
