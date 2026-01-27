pipeline {
    agent { label 'agent' }

    tools {
        jdk 'jdk21'
        nodejs 'node21'
    }

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
        BACKEND_IMAGE = "rjshk013/wanderlust-backend"
        FRONTEND_IMAGE = "rjshk013/wanderlust-frontend"
    }

    stages {

        stage('SCM Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/rjshk013/devops-projects.git'
            }
        }

        stage('Install Dependencies') {
            steps {
                parallel (
                    backend: {
                        dir('wanderlust-3tier-project/backend') {
                            sh "npm install || true"
                        }
                    },
                    frontend: {
                        dir('wanderlust-3tier-project/frontend') {
                            sh "npm install"
                        }
                    }
                )
            }
        }

        stage('Docker Build') {
            steps {
                dir('wanderlust-3tier-project') {
                    sh '''
                        docker build -t ${BACKEND_IMAGE}:${IMAGE_TAG} ./backend
                        docker build -t ${FRONTEND_IMAGE}:${IMAGE_TAG} ./frontend
                    '''
                }
            }
        }

        stage('Snyk Scanning') {
            parallel {

                stage('Frontend Dependency Scan') {
                    steps {
                        dir('wanderlust-3tier-project/frontend') {
                            snykSecurity(
                                snykInstallation: 'snyk',
                                snykTokenId: 'snyk-api',
                                targetFile: 'package.json',
                                projectName: 'wanderlust-frontend-src',
                                failOnIssues: false,
                                additionalArguments: "--severity-threshold=critical"
                            )
                        }
                    }
                }

                stage('Backend Dependency Scan') {
                    steps {
                        dir('wanderlust-3tier-project/backend') {
                            snykSecurity(
                                snykInstallation: 'snyk',
                                snykTokenId: 'snyk-api',
                                targetFile: 'package.json',
                                projectName: 'wanderlust-backend-src',
                                failOnIssues: false,
                                additionalArguments: "--severity-threshold=critical"
                            )
                        }
                    }
                }

                stage('Backend Image Scan') {
                    steps {
                        snykSecurity(
                            snykInstallation: 'snyk',
                            snykTokenId: 'synk-api',
                            failOnIssues: false,
                            projectName: 'wanderlust-backend-image',
                            additionalArguments: "--docker ${BACKEND_IMAGE}:${IMAGE_TAG} --severity-threshold=critical"
                        )
                    }
                }

                stage('Frontend Image Scan') {
                    steps {
                        snykSecurity(
                            snykInstallation: 'snyk',
                            snykTokenId: 'snyk-api',
                            failOnIssues: false,
                            projectName: 'wanderlust-frontend-image',
                            additionalArguments: "--docker ${FRONTEND_IMAGE}:${IMAGE_TAG} --severity-threshold=critical"
                        )
                    }
                }
            }
        }

        stage('Run SonarQube') {
            environment {
                scannerHome = tool 'sonar-scanner'
            }
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh """
                        ${scannerHome}/bin/sonar-scanner \
                        -Dsonar.projectKey=blog-app \
                        -Dsonar.projectName=blog-app \
                        -Dsonar.sources=wanderlust-3tier-project
                    """
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([string(credentialsId: 'docker-hub-token', variable: 'DOCKER_TOKEN')]) {
                    sh '''
                        echo "${DOCKER_TOKEN}" | docker login -u rjshk013 --password-stdin
                        docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                        docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Remote Deploy on EC2 Host with Docker Compose') {
            steps {
                sshagent(credentials: ['deploy-server-ssh']) {
                    sh '''
                        echo "🚀 Deploying on EC2 instance with docker compose..."
                        ssh -o StrictHostKeyChecking=no user@172.18.0.1 '
                            cd /home/user/devops-projects/wanderlust-3tier-project &&
                            docker compose build &&
                            docker compose up -d
                        '
                    '''
                }
            }
        }
    }


post {
    always {
        echo '📦 Pipeline execution completed'
        deleteDir()
    }
    success {
        echo "✅ Wanderlust pipeline succeeded: Build #${BUILD_NUMBER}"
    }
    failure {
        echo "❌ Wanderlust pipeline failed: Build #${BUILD_NUMBER}"
    }
}

