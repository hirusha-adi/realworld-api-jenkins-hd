pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 45, unit: 'MINUTES')
    }

    environment {
        APP_NAME = 'hirusha-sit223-realworld-api'

        COMPOSE_FILE = 'deploy/docker-compose.app.yml'

        DOCKER_IMAGE = 'hirushaadi/realworld-api'
        GITHUB_REPO = 'hirusha-adi/realworld-api-jenkins-hd'

        STAGING_PROJECT = 'hirusha-sit223-realworld-staging'
        STAGING_CONTAINER = 'hirusha-sit223-realworld-api-staging'
        STAGING_DB_CONTAINER = 'hirusha-sit223-realworld-db-staging'
        STAGING_URL = 'https://api-staging.hirusha.xyz/health'

        PROD_PROJECT = 'hirusha-sit223-realworld-prod'
        PROD_CONTAINER = 'hirusha-sit223-realworld-api-prod'
        PROD_DB_CONTAINER = 'hirusha-sit223-realworld-db-prod'
        PROD_URL = 'https://api.hirusha.xyz/health'

        DB_USER = 'realworld'
        DB_NAME = 'realworld'

        CADDY_NETWORK = 'intranet_1'
        DB_SERVICE = 'hirusha-sit223-db'
        API_SERVICE = 'hirusha-sit223-api'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.GIT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.GIT_COMMIT_FULL = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    env.VERSION = "v${BUILD_NUMBER}-${GIT_SHA}"
                    env.RELEASE_TAG = "v${BUILD_NUMBER}"
                    env.IMAGE_TAG = "${DOCKER_IMAGE}:${VERSION}"
                    env.IMAGE_LATEST = "${DOCKER_IMAGE}:latest"
                }

                sh '''
                    mkdir -p reports

                    echo "App: ${APP_NAME}" > reports/build-info.txt
                    echo "Build number: ${BUILD_NUMBER}" >> reports/build-info.txt
                    echo "Commit: ${GIT_COMMIT_FULL}" >> reports/build-info.txt
                    echo "Version: ${VERSION}" >> reports/build-info.txt
                    echo "Docker image: ${IMAGE_TAG}" >> reports/build-info.txt

                    cat reports/build-info.txt
                '''
            }
        }

        stage('Install Dependencies') {
            steps {
                sh '''
                    node --version
                    npm --version
                    npm ci
                '''
            }
        }

        stage('Build Application') {
            steps {
                sh '''
                    npx prisma generate --schema=src/prisma/schema.prisma
                    npx nx build api
                '''
            }
        }

        stage('Run Tests') {
            steps {
                withCredentials([
                    string(credentialsId: 'realworld-db-password', variable: 'DB_PASSWORD'),
                    string(credentialsId: 'realworld-jwt-secret', variable: 'JWT_SECRET_VALUE')
                ]) {
                    sh '''
                        mkdir -p reports/junit

                        TEST_DB="realworld-test-db-${BUILD_NUMBER}"

                        docker rm -f "${TEST_DB}" 2>/dev/null || true

                        docker run -d \
                          --name "${TEST_DB}" \
                          -e POSTGRES_USER="${DB_USER}" \
                          -e POSTGRES_PASSWORD="${DB_PASSWORD}" \
                          -e POSTGRES_DB="realworld_test" \
                          postgres:16-alpine

                        echo "Waiting for test database to start..."
                        sleep 15

                        export DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/realworld_test?schema=public"
                        export JWT_SECRET="${JWT_SECRET_VALUE}"

                        npx prisma migrate deploy --schema=src/prisma/schema.prisma || true

                        JEST_JUNIT_OUTPUT_DIR=reports/junit \
                        JEST_JUNIT_OUTPUT_NAME=jest-results.xml \
                        npx nx test api \
                          --coverage \
                          --ci \
                          --runInBand \
                          --reporters=default \
                          --reporters=jest-junit
                    '''
                }
            }

            post {
                always {
                    sh '''
                        docker rm -f "realworld-test-db-${BUILD_NUMBER}" 2>/dev/null || true
                    '''

                    junit allowEmptyResults: true, testResults: 'reports/junit/*.xml'

                    archiveArtifacts artifacts: 'coverage/**/*,reports/junit/**/*', allowEmptyArchive: true
                }
            }
        }

        stage('Code Quality') {
          steps {
              withCredentials([string(credentialsId: 'sonarqube-token', variable: 'SONAR_TOKEN')]) {
                  sh '''
                      echo "Running lint check..."
                      npx nx lint api || true

                      echo "Running SonarQube scan..."
                      sonar-scanner
                  '''
              }
          }
      }

        stage('Security Scan') {
            steps {
                withCredentials([
                    string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')
                ]) {
                    sh '''
                        mkdir -p reports/security

                        echo "Running npm audit..."
                        npm audit --json > reports/security/npm-audit.json || true

                        echo "Running Snyk..."
                        npx snyk test --json-file-output=reports/security/snyk.json || true
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts artifacts: 'reports/security/**/*', allowEmptyArchive: true
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                      -t "${IMAGE_TAG}" \
                      -t "${IMAGE_LATEST}" \
                      .
                '''
            }
        }

        stage('Create Build Artifact') {
            steps {
                sh '''
                    tar -czf "realworld-api-${VERSION}.tar.gz" \
                      dist \
                      package.json \
                      package-lock.json \
                      project.json \
                      nx.json \
                      src/prisma
                '''
            }

            post {
                success {
                    archiveArtifacts artifacts: 'realworld-api-*.tar.gz,reports/build-info.txt', fingerprint: true
                }
            }
        }

        stage('Deploy Staging') {
            steps {
                withCredentials([
                    string(credentialsId: 'realworld-db-password', variable: 'DB_PASSWORD'),
                    string(credentialsId: 'realworld-jwt-secret', variable: 'JWT_SECRET_VALUE'),
                    string(credentialsId: 'newrelic-license-key', variable: 'NEW_RELIC_LICENSE_KEY'),
                    string(credentialsId: 'newrelic-account-id', variable: 'NEW_RELIC_ACCOUNT_ID')
                ]) {
                    sh '''
                        mkdir -p reports

                        echo "Deploying to staging..."

                        docker network inspect "${CADDY_NETWORK}" >/dev/null 2>&1 || docker network create "${CADDY_NETWORK}"

                        cat > .env <<EOF
APP_IMAGE=${IMAGE_TAG}
APP_CONTAINER=${STAGING_CONTAINER}
DB_CONTAINER=${STAGING_DB_CONTAINER}
DB_HOST_ALIAS=${STAGING_CONTAINER}-db
APP_ENV=staging
GIT_COMMIT=${GIT_SHA}
JWT_SECRET=${JWT_SECRET_VALUE}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=${DB_NAME}
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${STAGING_CONTAINER}-db:5432/${DB_NAME}?schema=public
NEW_RELIC_LICENSE_KEY=${NEW_RELIC_LICENSE_KEY}
NEW_RELIC_ACCOUNT_ID=${NEW_RELIC_ACCOUNT_ID}
NEW_RELIC_APP_NAME=${APP_NAME}-staging
EOF

                        docker compose \
                          --env-file .env \
                          -p "${STAGING_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          down -v --remove-orphans || true

                        docker compose \
                          --env-file .env \
                          -p "${STAGING_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          up -d "${DB_SERVICE}"

                        echo "Waiting for staging database..."
                        sleep 15

                        docker compose \
                          --env-file .env \
                          -p "${STAGING_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          up -d "${API_SERVICE}"

                        echo "Waiting for staging API..."
                        sleep 20

                        curl --retry 10 \
                          --retry-delay 5 \
                          --retry-connrefused \
                          -f "${STAGING_URL}" \
                          -o reports/staging-health.json

                        rm -f .env

                        echo "Staging deployment completed."
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts artifacts: 'reports/staging*', allowEmptyArchive: true
                }
            }
        }

        stage('Release') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKERHUB_USER',
                        passwordVariable: 'DOCKERHUB_PASS'
                    ),
                    string(credentialsId: 'github-token', variable: 'GITHUB_TOKEN')
                ]) {
                    sh '''
                        mkdir -p reports/release

                        echo "Logging in to DockerHub..."
                        echo "${DOCKERHUB_PASS}" | docker login \
                          -u "${DOCKERHUB_USER}" \
                          --password-stdin

                        echo "Pushing Docker image..."
                        docker push "${IMAGE_TAG}"
                        docker push "${IMAGE_LATEST}"

                        echo "Creating GitHub release..."

                        cat > reports/release/github-release.json <<EOF
{
  "tag_name": "${RELEASE_TAG}",
  "target_commitish": "${GIT_COMMIT_FULL}",
  "name": "${RELEASE_TAG}",
  "body": "Automated Jenkins release. Docker image: ${IMAGE_TAG}",
  "draft": false,
  "prerelease": false
}
EOF

                        curl -X POST \
                          -H "Accept: application/vnd.github+json" \
                          -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                          "https://api.github.com/repos/${GITHUB_REPO}/releases" \
                          -d @reports/release/github-release.json \
                          -o reports/release/github-response.json \
                          || true

                        echo "Release stage completed."
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts artifacts: 'reports/release/**/*', allowEmptyArchive: true
                }
            }
        }

        stage('Deploy Production') {
            steps {
                withCredentials([
                    string(credentialsId: 'realworld-db-password', variable: 'DB_PASSWORD'),
                    string(credentialsId: 'realworld-jwt-secret', variable: 'JWT_SECRET_VALUE'),
                    string(credentialsId: 'newrelic-license-key', variable: 'NEW_RELIC_LICENSE_KEY'),
                    string(credentialsId: 'newrelic-account-id', variable: 'NEW_RELIC_ACCOUNT_ID')
                ]) {
                    sh '''
                        mkdir -p reports

                        echo "Deploying to production..."

                        cat > .env <<EOF
APP_IMAGE=${IMAGE_TAG}
APP_CONTAINER=${PROD_CONTAINER}
DB_CONTAINER=${PROD_DB_CONTAINER}
DB_HOST_ALIAS=${PROD_CONTAINER}-db
APP_ENV=production
GIT_COMMIT=${GIT_SHA}
JWT_SECRET=${JWT_SECRET_VALUE}
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}
POSTGRES_DB=${DB_NAME}
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@${PROD_CONTAINER}-db:5432/${DB_NAME}?schema=public
NEW_RELIC_LICENSE_KEY=${NEW_RELIC_LICENSE_KEY}
NEW_RELIC_ACCOUNT_ID=${NEW_RELIC_ACCOUNT_ID}
NEW_RELIC_APP_NAME=${APP_NAME}-production
EOF

                        docker compose \
                          --env-file .env \
                          -p "${PROD_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          down -v --remove-orphans || true

                        docker compose \
                          --env-file .env \
                          -p "${PROD_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          up -d "${DB_SERVICE}"

                        echo "Waiting for production database..."
                        sleep 15

                        docker compose \
                          --env-file .env \
                          -p "${PROD_PROJECT}" \
                          -f "${COMPOSE_FILE}" \
                          up -d "${API_SERVICE}"

                        echo "Waiting for production API..."
                        sleep 20

                        curl --retry 10 \
                          --retry-delay 5 \
                          --retry-connrefused \
                          -f "${PROD_URL}" \
                          -o reports/prod-health.json

                        rm -f .env

                        echo "Production deployment completed."
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts artifacts: 'reports/prod*', allowEmptyArchive: true
                }
            }
        }

        stage('Monitoring') {
            steps {
                sh '''
                    mkdir -p reports/monitoring

                    echo "Checking production health endpoint..."

                    curl -f "${PROD_URL}" -o reports/monitoring/production-health.json

                    echo "Monitoring check completed."
                '''
            }

            post {
                always {
                    archiveArtifacts artifacts: 'reports/monitoring/**/*', allowEmptyArchive: true
                }
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully."
            echo "Docker image: ${IMAGE_TAG}"
        }

        failure {
            echo "Pipeline failed. Check the failed stage above."
        }

        always {
            archiveArtifacts artifacts: 'reports/**/*', allowEmptyArchive: true
        }
    }
}