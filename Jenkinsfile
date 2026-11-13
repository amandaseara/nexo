pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(
            numToKeepStr: '10'
        ))
        skipDefaultCheckout(true)
    }

    environment {
        DATABASE_URL = 'sqlite+pysqlite:///:memory:'
        PYTHONDONTWRITEBYTECODE = '1'
        PIP_DISABLE_PIP_VERSION_CHECK = '1'
        IMAGE_NAME = 'ghcr.io/amandaseara/nexo-api'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Cloning Nexo repository...'
                checkout scm
            }
        }

        stage('Environment Setup') {
            steps {
                echo 'Checking Python environment...'

                sh '''
                    python3 --version
                    python3 -m venv .venv

                    ./.venv/bin/python -m pip install --upgrade pip
                    ./.venv/bin/pip install -r requirements-dev.txt
                '''
            }
        }

        stage('Tests') {
            steps {
                echo 'Running Nexo automated tests...'

                sh '''
                    mkdir -p reports/jenkins

                    set +e
                    ./.venv/bin/python -m pytest -v \
                        --junitxml=reports/jenkins/junit.xml \
                        > reports/jenkins/pytest.txt 2>&1

                    TEST_STATUS=$?

                    cat reports/jenkins/pytest.txt

                    exit $TEST_STATUS
                '''
            }
        }


        stage('Semgrep Security Scan') {
            steps {
                echo 'Running Semgrep security analysis...'

                sh '''
                    mkdir -p reports

                    set +e

                    /var/lib/jenkins/.local/bin/semgrep scan \
                        --config security/semgrep/rules.yml \
                        --text \
                        --error \
                        > reports/semgrep-report.txt 2>&1

                    SCAN_STATUS=$?

                    /var/lib/jenkins/.local/bin/semgrep scan \
                        --config security/semgrep/rules.yml \
                        --json \
                        --output reports/semgrep-report.json

                    JSON_STATUS=$?

                    echo "Semgrep exit code: $SCAN_STATUS"
                    echo "JSON report exit code: $JSON_STATUS"

                    cat reports/semgrep-report.txt

                    if [ "$JSON_STATUS" -ne 0 ]; then
                        exit "$JSON_STATUS"
                    fi

                    exit "$SCAN_STATUS"
                '''
            }
        }

        stage('Snyk Dependency Scan') {
            steps {
                echo 'Scanning Python dependencies with Snyk...'

                withCredentials([
                    string(
                        credentialsId: 'SNYK_TOKEN',
                        variable: 'SNYK_TOKEN'
                    )
                ]) {
                    sh '''
                        mkdir -p reports

                        set +e

                        snyk test \
                            --file=requirements.txt \
                            --command=./.venv/bin/python \
                            --json-file-output=reports/snyk-production.json \
                            > reports/snyk-production.txt 2>&1

                        PROD_STATUS=$?

                        snyk test \
                            --file=requirements-dev.txt \
                            --package-manager=pip \
                            --command=./.venv/bin/python \
                            --json-file-output=reports/snyk-development.json \
                            > reports/snyk-development.txt 2>&1

                        DEV_STATUS=$?

                        echo "Production scan exit code: $PROD_STATUS"
                        echo "Development scan exit code: $DEV_STATUS"

                        cat reports/snyk-production.txt
                        cat reports/snyk-development.txt

                        cat reports/snyk-production.txt \
                            reports/snyk-development.txt \
                            > reports/snyk-report.txt

                        if [ "$PROD_STATUS" -gt 1 ] || [ "$DEV_STATUS" -gt 1 ]; then
                            echo "SNYK ERROR: Dependency scanning failed."
                            exit 2
                        fi

                        python3 scripts/check_snyk.py
                    '''
                }
            }
        }

        stage('Docker Build') {
            steps {
                echo 'Building NEXO Docker image...'

                sh '''
                    docker build \
                        -f docker/Dockerfile \
                        -t ${IMAGE_NAME}:build-${BUILD_NUMBER} \
                        -t ${IMAGE_NAME}:latest \
                        .
                '''

                echo 'Docker image built successfully.'
            }
        }

        stage('Trivy Image Scan') {
            steps {
                echo 'Scanning NEXO Docker image with Trivy...'

                sh '''
                    mkdir -p reports

                    trivy image \
                        --scanners vuln \
                        --severity HIGH,CRITICAL \
                        --format table \
                        --output reports/trivy-image.txt \
                        ${IMAGE_NAME}:build-${BUILD_NUMBER}

                    trivy image \
                        --scanners vuln \
                        --format json \
                        --output reports/trivy-image.json \
                        ${IMAGE_NAME}:build-${BUILD_NUMBER}

                    cat reports/trivy-image.txt

                    echo "Checking critical vulnerabilities..."

                    trivy image \
                        --scanners vuln \
                        --severity CRITICAL \
                        --exit-code 1 \
                        ${IMAGE_NAME}:build-${BUILD_NUMBER}
                '''
            }
        }

        stage('Publish to GHCR') {
            steps {
                echo 'Publishing NEXO image to GitHub Container Registry...'

                withCredentials([
                    usernamePassword(
                        credentialsId: 'GHCR_CREDENTIALS',
                        usernameVariable: 'GHCR_USER',
                        passwordVariable: 'GHCR_TOKEN'
                    )
                ]) {
                    sh '''
                        echo "$GHCR_TOKEN" | docker login ghcr.io \
                            -u "$GHCR_USER" \
                            --password-stdin

                        docker push ${IMAGE_NAME}:build-${BUILD_NUMBER}
                        docker push ${IMAGE_NAME}:latest

                        docker logout ghcr.io
                    '''
                }

                echo 'NEXO image published successfully.'
            }
        }
    }

    post {
        always {
            echo 'Publishing test results...'

            junit(
                testResults: 'reports/jenkins/junit.xml',
                allowEmptyResults: true
            )

            archiveArtifacts(
                artifacts: 'reports/jenkins/*,reports/semgrep-report.*,reports/snyk-*,reports/trivy-image.*',
                allowEmptyArchive: true
            )
        }

        success {
            echo 'NEXO CI PIPELINE: SUCCESS'
        }

        failure {
            echo 'NEXO CI PIPELINE: FAILURE'
        }
    }
}
