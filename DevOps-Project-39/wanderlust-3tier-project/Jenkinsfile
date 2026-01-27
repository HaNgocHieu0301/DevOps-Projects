pipeline {
    agent { label 'agent' }

    tools {
        jdk 'jdk21'
        nodejs 'node21'
    }

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
        BACKEND_IMAGE = "NotHarshhaa/wanderlust-backend"
        FRONTEND_IMAGE = "NotHarshhaa/wanderlust-frontend"
    }

    stages {
        stage('SCM Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/NotHarshhaa/DevOps-Projects.git'
            }
        }

        stage('Install Dependencies') {
            steps {
                dir('wanderlust-3tier-project/backend') {
                    sh "npm install || true"
                }
                dir('wanderlust-3tier-project/frontend') {
                    sh "npm install"
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

        stage('Trivy Filesystem Scan') {
            steps {
                script {
                    def trivyDir = "${WORKSPACE}/trivy-reports"
                    sh "mkdir -p ${trivyDir}"
                    
                    // Define targets for filesystem scanning
                    def fsTargets = [
                        [path: "${WORKSPACE}/wanderlust-3tier-project/backend", name: "backend-fs"],
                        [path: "${WORKSPACE}/wanderlust-3tier-project/frontend", name: "frontend-fs"]
                    ]
                    
                    // Run filesystem scans for source code vulnerabilities
                    for (target in fsTargets) {
                        echo "🔍 Scanning filesystem at ${target.path}..."
                        
                        // Scan for vulnerabilities in dependencies
                        sh """
                            docker run --rm \
                                -v ${target.path}:/target \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy fs \
                                --security-checks vuln \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format table \
                                /target > ${trivyDir}/trivy-${target.name}-vuln.txt
                        """
                        
                        // Scan for security issues in configuration files
                        sh """
                            docker run --rm \
                                -v ${target.path}:/target \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy fs \
                                --security-checks config \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format json \
                                /target > ${trivyDir}/trivy-${target.name}-config.json
                        """
                        
                        // Generate an HTML report for easier reading
                        sh """
                            docker run --rm \
                                -v ${target.path}:/target \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy fs \
                                --security-checks vuln,config \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format template \
                                --template '@/contrib/html.tpl' \
                                /target > ${trivyDir}/trivy-${target.name}-report.html
                        """
                    }
                    
                    // Add filesystem scan summary to the main report
                    sh """
                        echo "\\n## Source Code Vulnerability Scan" >> ${trivyDir}/summary.md
                        echo "### Backend Source Vulnerabilities" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                        grep -A 10 "CRITICAL\\|HIGH" ${trivyDir}/trivy-backend-fs-vuln.txt | head -20 >> ${trivyDir}/summary.md
                        echo "\\n... (See full report for more details)" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                        
                        echo "\\n### Frontend Source Vulnerabilities" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                        grep -A 10 "CRITICAL\\|HIGH" ${trivyDir}/trivy-frontend-fs-vuln.txt | head -20 >> ${trivyDir}/summary.md
                        echo "\\n... (See full report for more details)" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                    """
                }
            }
        }

        stage('Docker Build') {
            steps {
                dir('wanderlust-3tier-project') {
                    sh '''
                        docker build -t ${BACKEND_IMAGE}:${IMAGE_TAG} -f ./backend/Dockerfile_optimised1  ./backend
                        docker build -t ${FRONTEND_IMAGE}:${IMAGE_TAG} -f ./frontend/Dockerfile_optimized1 ./frontend
                    '''
                }
            }
        }

        stage('Trivy Image Scan') {
            steps {
                script {
                    def trivyDir = "${WORKSPACE}/trivy-reports"
                    
                    // Define scan configurations
                    def images = [
                        [name: "${BACKEND_IMAGE}:${IMAGE_TAG}", type: "backend"],
                        [name: "${FRONTEND_IMAGE}:${IMAGE_TAG}", type: "frontend"]
                    ]

                    // Run scans with multiple output formats
                    for (img in images) {
                        echo "🔍 Scanning ${img.name}..."
                        
                        // HTML Report - Highly readable in browser
                        sh """
                            docker run --rm \
                                -v /var/run/docker.sock:/var/run/docker.sock \
                                -v \$HOME/.trivy-cache:/root/.cache/ \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy image \
                                --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format template \
                                --template '@/contrib/html.tpl' \
                                ${img.name} > ${trivyDir}/trivy-${img.type}-report.html
                        """
                        
                        // Table format for console and archive
                        sh """
                            docker run --rm \
                                -v /var/run/docker.sock:/var/run/docker.sock \
                                -v \$HOME/.trivy-cache:/root/.cache/ \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy image \
                                --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format table \
                                ${img.name} > ${trivyDir}/trivy-${img.type}-report.txt
                        """
                        
                        // JSON format for potential programmatic processing
                        sh """
                            docker run --rm \
                                -v /var/run/docker.sock:/var/run/docker.sock \
                                -v \$HOME/.trivy-cache:/root/.cache/ \
                                -v ${trivyDir}:/reports \
                                aquasec/trivy image \
                                --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                --format json \
                                ${img.name} > ${trivyDir}/trivy-${img.type}-report.json
                        """
                    }
                    
                    // Generate combined summary report - FIXED SECTION
                    sh """
                        echo "# Trivy Vulnerability Summary Report" > ${trivyDir}/summary.md
                        echo "## Images Scanned" >> ${trivyDir}/summary.md
                        echo "- ${BACKEND_IMAGE}:${IMAGE_TAG}" >> ${trivyDir}/summary.md
                        echo "- ${FRONTEND_IMAGE}:${IMAGE_TAG}" >> ${trivyDir}/summary.md
                        echo "\\n## Backend Container Vulnerabilities" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                        grep -A 10 "CRITICAL\\|HIGH" ${trivyDir}/trivy-backend-report.txt | head -20 >> ${trivyDir}/summary.md
                        echo "\\n... (See full report for more details)" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                        echo "\\n## Frontend Container Vulnerabilities" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md 
                        grep -A 10 "CRITICAL\\|HIGH" ${trivyDir}/trivy-frontend-report.txt | head -20 >> ${trivyDir}/summary.md
                        echo "\\n... (See full report for more details)" >> ${trivyDir}/summary.md
                        echo '```' >> ${trivyDir}/summary.md
                    """
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([string(credentialsId: 'docker-hub-token', variable: 'DOCKER_TOKEN')]) {
                    sh '''
                        echo "${DOCKER_TOKEN}" | docker login -u NotHarshhaa --password-stdin
                        docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                        docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                    '''
                }
            }
        }

        stage('Remote Deploy on Host with Docker Compose') {
            steps {
                sshagent(credentials: ['deploy-server-ssh']) {
                    sh '''
                        echo "🚀 Deploying on host with docker compose..."
                        ssh -o StrictHostKeyChecking=no user@172.18.0.1 '
                            cd /home/user/devops-projects/wanderlust-3tier-project &&
                            docker compose pull &&
                            docker compose up -d
                        '
                    '''
                }
            }
        }
    } 
post {
    always {
        // Archive all Trivy reports
        archiveArtifacts artifacts: 'trivy-reports/**', fingerprint: true
    }
    success {
        slackSend(
            channel: "#jenkins-alert",
            color: "good",
            message: "✅ *BUILD SUCCESSFUL:* ${env.JOB_NAME} #${env.BUILD_NUMBER}\n🔗 <${env.BUILD_URL}|View Build Details>"
        )
    }
    failure {
        slackSend(
            channel: "#jenkins-alert",
            color: "danger",
            message: "❌ *BUILD FAILED:* ${env.JOB_NAME} #${env.BUILD_NUMBER}\n🔗 <${env.BUILD_URL}|View Build Details>"
        )
    }
}
}
