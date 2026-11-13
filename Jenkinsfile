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
    }

    post {
        always {
            echo 'Publishing test results...'

            junit(
                testResults: 'reports/jenkins/junit.xml',
                allowEmptyResults: true
            )

            archiveArtifacts(
                artifacts: 'reports/jenkins/*,reports/semgrep-report.*,reports/snyk-*',
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
