def dockerHubRepo = "sahal56/netflix" // Your Docker Hub repository
def email = "sahalpathan5601@gmail.com" // Your E-mail
def slackChannel = "#jenkins" // Your Slack Channel

pipeline {
    agent any

    tools{
        jdk 'jdk17'
        nodejs 'node16'
    }

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        TMDB_API_KEY = credentials('tmdbApiKey')
        OWASP_NVD_API_KEY = credentials('owaspNvdApiKey')
    }

    stages {

        stage('Prepare Workspace'){
            steps {
                cleanWs()
                checkout scm
            }
        }

        stage("Sonarqube Analysis"){
            steps{
                withSonarQubeEnv('sonar-server') {
                    sh '''
                    java -version
                    $SCANNER_HOME/bin/sonar-scanner \
                    -Dsonar.projectName=Netflix \
                    -Dsonar.projectKey=Netflix
                    '''
                }
            }
        }

        stage("Quality Gate"){
           steps {
                script {
                    timeout(time: 5, unit: 'MINUTES') {
                        // Not stopping pipeline
                        waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token'
                    }
                }
            } 
        }

        stage('Install Dependencies') {
            steps {
                sh "npm install --no-audit"
            }
        }

        stage('OWASP FS SCAN') {
            steps {
                dependencyCheck additionalArguments: """
                --scan ./ \
                --disableYarnAudit \
                --disableNodeAudit \
                --cveValidForHours 24 \
                --format XML \
                --out dependency-check-report \
                --nvdApiKey ${env.OWASP_NVD_API_KEY}
                """, odcInstallation: 'DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
            // Truncated NVD Data (for speed) : cveValidForHours 24 h, CVE which is updated 24 hours ago. So it will be faster
        }

        stage('TRIVY FS SCAN') {
            steps {
                sh "trivy fs . > trivy_file_scan.txt"
            }
        }

        stage("BUILD : Docker Build & Push"){
            steps{
                script{
                   withDockerRegistry(credentialsId: 'dockerhub-id', toolName: 'docker'){   
                       sh "docker build --build-arg TMDB_V3_API_KEY=${env.TMDB_API_KEY} -t ${dockerHubRepo}:${env.BUILD_NUMBER} ."
                       sh "docker tag ${dockerHubRepo}:${env.BUILD_NUMBER} ${dockerHubRepo}:latest"
                       sh "docker push ${dockerHubRepo}:${env.BUILD_NUMBER}"
                       sh "docker push ${dockerHubRepo}:latest"
                    }
                }
            }
        }

        stage("TRIVY IMAGE SCAN"){
            steps{
                sh "trivy image ${dockerHubRepo}:latest > trivy_image_scan.txt" 
            }
        }

        // Here New Job will take care of CD - ArgoCD will do Deployment
        // stage('Trigger Update Manifest Job'){
        //     steps{
        //         echo "Triggering updatemanifestjob"
        //         build job: 'updatemanifestjob', parameters: [string(name: 'DOCKERTAG', value: env.BUILD_NUMBER)]
        //     }
        // }

        stage('DEPLOY : Run the latest container on Jenkins EC2'){
            steps{
                sh "docker rm -f netflix || true"
                sh "docker run -d --name netflix -p 8081:80 ${dockerHubRepo}:latest"
            }
        }

    }// stages end

    post {
        always {
            // Email
            script {
                def buildStatus = currentBuild.currentResult
                def buildUser = currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')[0]?.userId ?: 'Jenkins'
                def fileReportExists = fileExists('trivy_file_scan.txt') && fileExists('trivy_image_scan.txt')

                emailext (
                    subject: "${env.JOB_NAME}: ${buildStatus}",
                    body: """
                    <p>This is a Jenkins NETFLIX CI pipeline status.</p>
                    <p>Project: ${env.JOB_NAME}</p>
                    <p>Build Number: ${env.BUILD_NUMBER}</p>
                    <p>Build Status: ${buildStatus}</p>
                    <p>Started by: ${buildUser}</p>
                    <p>Build URL: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                    """,
                    to: "${email}",
                    mimeType: 'text/html',
                    attachmentsPattern: fileReportExists ? 'trivy_file_scan.txt,trivy_image_scan.txt' : ''
                )
            }

            // Slack
            script {
                // if env var of slack is not null and not empty, then proceed
                if (slackChannel != null && !slackChannel.trim().isEmpty()) {
                    slackSend channel: slackChannel, // Use the variable here
                    message: "${env.JOB_NAME} Status: ${currentBuild.currentResult} #${env.BUILD_NUMBER} ${BUILD_URL}"
                } else {
                    echo "Slack channel not defined or empty. Skipping Slack notification."
                }
            }
        }
    }
    // post stage ends

}
