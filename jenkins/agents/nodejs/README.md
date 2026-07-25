# Node.js Jenkins agent

The `nodejs` agent contains Node.js LTS, npm, Git, Python, make, GCC, and G++.
Native npm addons are supported and verified by compiling an N-API fixture with
the `node-gyp` bundled in npm during every image build.

Use it with:

```groovy
agent { label 'nodejs' }
```

## Typical Node.js pipeline

The example assumes the project defines `lint`, `test`, and `build` scripts in
`package.json`.

```groovy
@Library('jenkins_libs') _

pipeline {
  agent { label 'nodejs' }

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

    stage('Dependencies') {
      steps {
        npmInstall()
      }
    }

    stage('Quality') {
      parallel {
        stage('Lint') {
          steps {
            npmLint()
          }
        }
        stage('Tests') {
          steps {
            npmTest(ARGS: ['--coverage'])
          }
        }
      }
    }

    stage('Build') {
      steps {
        npmBuild()
      }
    }

    stage('Archive') {
      steps {
        archiveBuildArtifacts(
          ITEMS: [[
            SOURCE: 'dist',
            NAME: "nodejs-${env.BUILD_NUMBER}.tar.gz",
            FORMAT: 'tar.gz'
          ]]
        )
      }
    }
  }
}
```

For a monorepo, pass `PROJECT_DIR`, for example
`npmInstall(PROJECT_DIR: 'services/api')`. Use
`npmRun(SCRIPT: 'typecheck')` for project-specific scripts.
