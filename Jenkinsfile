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

        K8S_NAMESPACE = 'nexo'
        HELM_RELEASE = 'nexo'
        DB_SECRET_NAME = 'nexo-secret'
    }

    stages {

        stage('Checkout') {
            steps {
                echo 'Cloning NEXO repository...'
                checkout scm

                script {
                    env.APP_VERSION = sh(
                        script: "awk '/^appVersion:/ {print \$2}' helm-chart/Chart.yaml | tr -d '\"'",
                        returnStdout: true
                    ).trim()

                    if (!(env.APP_VERSION ==~ /\d+\.\d+\.\d+/)) {
                        error("Invalid application version: ${env.APP_VERSION}")
                    }

                    env.GIT_SHORT_SHA = sh(
                        script: 'git rev-parse --short=12 HEAD',
                        returnStdout: true
                    ).trim()

                    env.IMAGE_TAG = "${env.APP_VERSION}-build-${env.BUILD_NUMBER}-${env.GIT_SHORT_SHA}"
                }

                echo "Application version: ${env.APP_VERSION}"
                echo "Git commit: ${env.GIT_SHORT_SHA}"
                echo "Image tag: ${env.IMAGE_TAG}"
            }
        }

        stage('Environment Setup') {
            steps {
                echo 'Checking required tools...'

                sh '''
                    set -e

                    export PATH="$HOME/.local/bin:$PATH"

                    for tool in python3 docker semgrep snyk trivy kubectl helm; do
                        if ! command -v "$tool" >/dev/null 2>&1; then
                            echo "ERROR: Required tool not found: $tool"
                            exit 1
                        fi
                    done

                    python3 --version
                    docker --version
                    semgrep --version
                    snyk --version
                    trivy --version
                    kubectl version --client
                    helm version

                    mkdir -p reports/jenkins

                    python3 -m venv .venv

                    ./.venv/bin/python -m pip install --upgrade pip
                    ./.venv/bin/pip install -r requirements-dev.txt

                    ./.venv/bin/python -m pip check
                '''
            }
        }

        stage('Tests') {
            steps {
                echo 'Running NEXO automated tests...'

                sh '''
                    mkdir -p reports/jenkins

                    set +e

                    ./.venv/bin/python -m pytest -v \
                        --junitxml=reports/jenkins/junit.xml \
                        > reports/jenkins/pytest.txt 2>&1

                    TEST_STATUS=$?

                    cat reports/jenkins/pytest.txt

                    exit "$TEST_STATUS"
                '''
            }
        }

        stage('Semgrep Security Scan') {
            steps {
                echo 'Running Semgrep security analysis...'

                sh '''
                    export PATH="$HOME/.local/bin:$PATH"

                    mkdir -p reports

                    set +e

                    semgrep scan \
                        --config security/semgrep/rules.yml \
                        --text \
                        --error \
                        > reports/semgrep-report.txt 2>&1

                    SCAN_STATUS=$?

                    semgrep scan \
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
                        set +x

                        mkdir -p reports

                        rm -f reports/snyk-production.json \
                              reports/snyk-development.json

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

                        if [ ! -s reports/snyk-production.json ] || \
                           [ ! -s reports/snyk-development.json ]; then
                            echo "SNYK ERROR: Missing JSON reports."
                            exit 2
                        fi

                        ./.venv/bin/python scripts/check_snyk.py
                    '''
                }
            }
        }

        stage('Docker Build') {
            steps {
                echo "Building NEXO image: ${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                sh '''
                    set -e

                    docker build \
                        -f docker/Dockerfile \
                        --build-arg APP_VERSION="${APP_VERSION}" \
                        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
                        .

                    docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --format='{{.Id}}' \
                        > reports/jenkins/image-id.txt

                    docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --format='{{.Config.User}}' \
                        > reports/jenkins/image-user.txt

                    echo "Container user:"
                    cat reports/jenkins/image-user.txt

                    if [ "$(cat reports/jenkins/image-user.txt)" != "10001:10001" ]; then
                        echo "ERROR: Unexpected container UID/GID."
                        exit 1
                    fi
                '''

                echo 'Docker image built successfully.'
            }
        }

        stage('Trivy Image Scan') {
            steps {
                echo 'Scanning NEXO Docker image with Trivy...'

                sh '''
                    set -e

                    mkdir -p reports

                    trivy image \
                        --scanners vuln \
                        --severity HIGH,CRITICAL \
                        --format table \
                        --output reports/trivy-image.txt \
                        "${IMAGE_NAME}:${IMAGE_TAG}"

                    trivy image \
                        --scanners vuln \
                        --format json \
                        --output reports/trivy-image.json \
                        "${IMAGE_NAME}:${IMAGE_TAG}"

                    cat reports/trivy-image.txt

                    echo "Checking critical vulnerabilities..."

                    trivy image \
                        --scanners vuln \
                        --severity CRITICAL \
                        --exit-code 1 \
                        "${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        stage('Helm Chart Validation') {
            steps {
                echo 'Validating NEXO Helm Chart...'

                sh '''
                    set -e

                    mkdir -p reports/jenkins

                    helm lint ./helm-chart \
                        -f helm-chart/values-dev.yaml \
                        > reports/jenkins/helm-lint-dev.txt 2>&1 \
                        || {
                            cat reports/jenkins/helm-lint-dev.txt
                            exit 1
                        }

                    cat reports/jenkins/helm-lint-dev.txt

                    helm lint ./helm-chart \
                        -f helm-chart/values-prod.yaml \
                        > reports/jenkins/helm-lint-prod.txt 2>&1 \
                        || {
                            cat reports/jenkins/helm-lint-prod.txt
                            exit 1
                        }

                    cat reports/jenkins/helm-lint-prod.txt

                    helm template "${HELM_RELEASE}" ./helm-chart \
                        --namespace "${K8S_NAMESPACE}" \
                        -f helm-chart/values-dev.yaml \
                        --set-string image.tag="${IMAGE_TAG}" \
                        > reports/jenkins/helm-rendered.yaml

                    echo "Helm Chart validated successfully."
                '''
            }
        }

        stage('Publish to GHCR') {
            steps {
                echo "Publishing ${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                withCredentials([
                    usernamePassword(
                        credentialsId: 'GHCR_CREDENTIALS',
                        usernameVariable: 'GHCR_USER',
                        passwordVariable: 'GHCR_TOKEN'
                    )
                ]) {
                    sh '''
                        set +x
                        set -e

                        trap 'docker logout ghcr.io >/dev/null 2>&1 || true' EXIT

                        printf '%s' "$GHCR_TOKEN" | docker login ghcr.io \
                            -u "$GHCR_USER" \
                            --password-stdin

                        docker push "${IMAGE_NAME}:${IMAGE_TAG}"
                    '''
                }

                echo 'NEXO image published successfully.'
            }
        }

        stage('Kubernetes Preflight') {
            steps {
                echo 'Checking Kubernetes cluster and database Secret...'

                sh '''
                    set -e

                    mkdir -p reports/jenkins

                    kubectl config current-context

                    if ! kubectl cluster-info \
                        > reports/jenkins/cluster-info.txt 2>&1; then

                        cat reports/jenkins/cluster-info.txt

                        echo "ERROR: Kubernetes cluster is unavailable."
                        echo "Verify Minikube and Jenkins kubeconfig."

                        exit 1
                    fi

                    cat reports/jenkins/cluster-info.txt

                    kubectl get nodes

                    if ! kubectl get namespace "${K8S_NAMESPACE}" \
                        >/dev/null 2>&1; then

                        echo "ERROR: Namespace ${K8S_NAMESPACE} is missing or inaccessible."

                        exit 1
                    fi

                    if ! kubectl get secret "${DB_SECRET_NAME}" \
                        --namespace "${K8S_NAMESPACE}" \
                        >/dev/null 2>&1; then

                        echo "ERROR: Database Secret is missing or inaccessible."
                        echo "Initialize the cluster using scripts/create-db-secret.sh."

                        exit 1
                    fi

                    echo "Kubernetes preflight checks completed."
                '''
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                echo "Deploying NEXO ${env.IMAGE_TAG} to Kubernetes..."

                sh '''
                    set -e

                    mkdir -p reports/jenkins

                    echo "Deploying image: ${IMAGE_NAME}:${IMAGE_TAG}"

                    helm upgrade --install "${HELM_RELEASE}" ./helm-chart \
                        --namespace "${K8S_NAMESPACE}" \
                        --create-namespace \
                        -f helm-chart/values.yaml \
                        -f helm-chart/values-dev.yaml \
                        --set-string image.repository="${IMAGE_NAME}" \
                        --set-string image.tag="${IMAGE_TAG}" \
                        --set-string database.existingSecret="${DB_SECRET_NAME}" \
                        --atomic \
                        --wait \
                        --wait-for-jobs \
                        --timeout 10m \
                        > reports/jenkins/helm-deploy.txt 2>&1 \
                        || {
                            cat reports/jenkins/helm-deploy.txt

                            echo "ERROR: Helm deployment failed."

                            kubectl get pods \
                                --namespace "${K8S_NAMESPACE}" || true

                            kubectl get events \
                                --namespace "${K8S_NAMESPACE}" \
                                --sort-by=.metadata.creationTimestamp || true

                            exit 1
                        }

                    cat reports/jenkins/helm-deploy.txt

                    echo "Checking Kubernetes rollout..."

                    kubectl rollout status \
                        deployment/"${HELM_RELEASE}-api" \
                        --namespace "${K8S_NAMESPACE}" \
                        --timeout=180s \
                        > reports/jenkins/rollout.txt 2>&1 \
                        || {
                            cat reports/jenkins/rollout.txt
                            exit 1
                        }

                    cat reports/jenkins/rollout.txt

                    echo "Checking deployed image..."

                    kubectl get deployment "${HELM_RELEASE}-api" \
                        --namespace "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[?(@.name=="api")].image}' \
                        > reports/jenkins/deployed-image.txt

                    EXPECTED_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
                    ACTUAL_IMAGE=$(cat reports/jenkins/deployed-image.txt)

                    echo "Expected image: $EXPECTED_IMAGE"
                    echo "Deployed image: $ACTUAL_IMAGE"

                    if [ "$ACTUAL_IMAGE" != "$EXPECTED_IMAGE" ]; then
                        echo "ERROR: Deployed image does not match expected image."
                        exit 1
                    fi

                    kubectl get pods \
                        --namespace "${K8S_NAMESPACE}" \
                        > reports/jenkins/pods.txt

                    kubectl get services \
                        --namespace "${K8S_NAMESPACE}" \
                        > reports/jenkins/services.txt

                    cat reports/jenkins/pods.txt
                    cat reports/jenkins/services.txt

                    echo "Deployment image validated successfully."
                '''
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
            echo 'NEXO CI/CD PIPELINE: SUCCESS'
        }

        failure {
            echo 'NEXO CI/CD PIPELINE: FAILURE'
        }
    }
}
