// =============================================================================
// jenkins_pipeline.groovy
// Declarative Jenkins Pipeline for Infrastructure Deployment
// Author: Manicharan Ravi
// =============================================================================

pipeline {
    agent any

    parameters {
        choice(name: 'ENVIRONMENT',   choices: ['staging', 'production'], description: 'Target environment')
        choice(name: 'CLOUD',         choices: ['aws', 'azure', 'both'],  description: 'Target cloud provider')
        booleanParam(name: 'DESTROY', defaultValue: false,                description: 'Destroy infrastructure (danger!)')
    }

    environment {
        TF_DIR_AWS   = "terraform/aws"
        TF_DIR_AZURE = "terraform/azure"
        AWS_REGION   = "eu-central-1"
    }

    options {
        timeout(time: 60, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branch: ${env.GIT_BRANCH} | Environment: ${params.ENVIRONMENT}"
            }
        }

        stage('Validate') {
            parallel {
                stage('Terraform Validate — AWS') {
                    when { expression { params.CLOUD in ['aws', 'both'] } }
                    steps {
                        dir(env.TF_DIR_AWS) {
                            sh 'terraform init -backend=false'
                            sh 'terraform validate'
                            sh 'terraform fmt -check'
                        }
                    }
                }
                stage('Terraform Validate — Azure') {
                    when { expression { params.CLOUD in ['azure', 'both'] } }
                    steps {
                        dir(env.TF_DIR_AZURE) {
                            sh 'terraform init -backend=false'
                            sh 'terraform validate'
                            sh 'terraform fmt -check'
                        }
                    }
                }
            }
        }

        stage('Plan') {
            parallel {
                stage('Plan — AWS') {
                    when { expression { params.CLOUD in ['aws', 'both'] } }
                    steps {
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "aws-${params.ENVIRONMENT}"]]) {
                            dir(env.TF_DIR_AWS) {
                                sh "terraform init"
                                sh "terraform plan -var='environment=${params.ENVIRONMENT}' -out=tfplan-aws"
                                sh "terraform show -no-color tfplan-aws > tfplan-aws.txt"
                            }
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: "${env.TF_DIR_AWS}/tfplan-aws.txt"
                        }
                    }
                }
                stage('Plan — Azure') {
                    when { expression { params.CLOUD in ['azure', 'both'] } }
                    steps {
                        withCredentials([azureServicePrincipal(credentialsId: "azure-${params.ENVIRONMENT}")]) {
                            dir(env.TF_DIR_AZURE) {
                                sh "terraform init"
                                sh "terraform plan -var='environment=${params.ENVIRONMENT}' -out=tfplan-azure"
                                sh "terraform show -no-color tfplan-azure > tfplan-azure.txt"
                            }
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: "${env.TF_DIR_AZURE}/tfplan-azure.txt"
                        }
                    }
                }
            }
        }

        stage('Approval — Production') {
            when {
                allOf {
                    expression { params.ENVIRONMENT == 'production' }
                    expression { !params.DESTROY }
                }
            }
            steps {
                input message: "Deploy to PRODUCTION? Review the plan artifacts before approving.",
                      ok: 'Deploy',
                      submitter: 'team-lead,change-manager'
            }
        }

        stage('Apply') {
            when { expression { !params.DESTROY } }
            parallel {
                stage('Apply — AWS') {
                    when { expression { params.CLOUD in ['aws', 'both'] } }
                    steps {
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: "aws-${params.ENVIRONMENT}"]]) {
                            dir(env.TF_DIR_AWS) {
                                sh "terraform apply -auto-approve tfplan-aws"
                            }
                        }
                    }
                }
                stage('Apply — Azure') {
                    when { expression { params.CLOUD in ['azure', 'both'] } }
                    steps {
                        withCredentials([azureServicePrincipal(credentialsId: "azure-${params.ENVIRONMENT}")]) {
                            dir(env.TF_DIR_AZURE) {
                                sh "terraform apply -auto-approve tfplan-azure"
                            }
                        }
                    }
                }
            }
        }

        stage('Post-Deploy Validation') {
            when { expression { !params.DESTROY } }
            steps {
                echo "Running post-deploy validation..."
                sh '''
                    # Validate AWS backup vault exists
                    aws backup list-backup-vaults --region $AWS_REGION \
                        --query "BackupVaultList[?BackupVaultName!=null].BackupVaultName" \
                        --output text
                '''
            }
        }
    }

    post {
        success {
            echo "✅ Pipeline completed successfully — ${params.ENVIRONMENT} | ${params.CLOUD}"
        }
        failure {
            echo "❌ Pipeline failed — check logs and initiate rollback if needed"
        }
        always {
            cleanWs()
        }
    }
}
