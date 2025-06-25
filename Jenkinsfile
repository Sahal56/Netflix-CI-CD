def dockerHubRepo = "sahal56/netflix" // Your Docker Hub repository
def email = "sahalpathan5601@gmail.com" // Your E-mail

pipeline {
    agent any

    tools{
        jdk 'jdk17'
        nodejs 'node16'
    }

    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        SECRETS_API_KEYS = credentials('jenkins/apiKeys') // Loads the entire JSON secret from AWS Secrets Manager
        SLACK_CHANNEL = '#jenkins' // Your Slack Channel Name
    }

    stages {

        stage('Parsing API Keys'){
            steps{
                script{
                    def parsed = readJSON text: env.SECRETS_API_KEYS
                    env.TMDB_API_KEY = parsed.tmdbApiKey
                    env.OWASP_NVD_API_KEY = parsed.owaspNvdApiKey
                }
            }
        }


        stage('Clean Workspace'){
            steps{
                cleanWs()
            }
        }

        stage('Checkout from Git'){
            steps{
                checkout scm

                // If Jenkinsfile is stored in another repo
                // [declare in global] def gitRepo = "https://github.com/<username>/<repo-name>.git"
                // git branch: 'main', url: "${gitRepo}" 
            }
        }

        stage("Sonarqube Analysis"){
            steps{
                withSonarQubeEnv('sonar-server') {
                    sh ''' $SCANNER_HOME/bin/sonar-scanner \
                    -Dsonar.projectName=Netflix \
                    -Dsonar.projectKey=Netflix '''
                }
            }
        }

        stage("Quality Gate"){
           steps {
                script {
                    // Not stopping pipeline
                    waitForQualityGate abortPipeline: false, credentialsId: 'sonar-token' 
                }
            } 
        }

        stage('Install Dependencies') {
            steps {
                sh "npm install"
            }
        }

        stage('OWASP FS SCAN') {
            steps {
                dependencyCheck additionalArguments: "--scan ./ --disableYarnAudit --disableNodeAudit --nvdApiKey ${env.OWASP_NVD_API_KEY}", odcInstallation: 'DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
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
                sh '''
                docker rm -f netflix || true
                docker run -d --name netflix -p 8081:80 ${dockerHubRepo}:latest
                '''
            }
        }

    }// stages end

    post {
        always {
            // Email
            script {
                def buildStatus = currentBuild.currentResult
                def buildUser = currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause')[0]?.userId ?: 'Github User'
                emailext (
                    subject: "Pipeline ${buildStatus}: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                    body: """
                    <p>This is a Jenkins NETFLIX CICD pipeline status.</p>
                    <p>Project: ${env.JOB_NAME}</p>
                    <p>Build Number: ${env.BUILD_NUMBER}</p>
                    <p>Build Status: ${buildStatus}</p>
                    <p>Started by: ${buildUser}</p>
                    <p>Build URL: <a href="${env.BUILD_URL}">${env.BUILD_URL}</a></p>
                    """,
                    to: "${email}",
                    mimeType: 'text/html',
                    attachmentsPattern: 'trivy_file_scan.txt,trivy_image_scan.txt'
                )
            }

            // Slack
            script {
                // if env var of slack is not null and not empty, then proceed
                if (env.SLACK_CHANNEL != null && !env.SLACK_CHANNEL.trim().isEmpty()) {
                    slackSend channel: env.SLACK_CHANNEL, // Use the variable here
                    message: "Find Status of Pipeline:- ${currentBuild.currentResult} ${env.JOB_NAME} #${env.BUILD_NUMBER} ${BUILD_URL}"
                } else {
                    echo "Slack channel not defined or empty. Skipping Slack notification."
                }
            }
        }
    }
    // post stage ends
}
