pipeline {
    agent any

    environment {
        IMAGE_NAME = "ghcr.io/encorajamento/evolution-go"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
                // whatsmeow-lib é submodule git — `checkout scm` por padrão
                // não inicializa submódulos. Sem isso o Dockerfile falha
                // no COPY whatsmeow-lib/ pra pasta vazia.
                sh 'git submodule update --init --recursive'
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                    set -e

                    COMMIT=$(git rev-parse --short HEAD)
                    echo "Building Evolution Go - Commit: $COMMIT"

                    docker build \
                      -t $IMAGE_NAME:$COMMIT \
                      -t $IMAGE_NAME:latest \
                      --build-arg VERSION=$COMMIT \
                      .
                '''
            }
        }

        stage('Login & Push GHCR') {
            steps {
                withCredentials([string(credentialsId: 'ghcr-token', variable: 'GHCR_TOKEN')]) {
                    sh '''
                        set -e

                        echo "$GHCR_TOKEN" | docker login ghcr.io -u encorajamento --password-stdin

                        COMMIT=$(git rev-parse --short HEAD)

                        docker push $IMAGE_NAME:$COMMIT
                        docker push $IMAGE_NAME:latest
                    '''
                }
            }
        }

        stage('Deploy Swarm') {
            // Deploy só dispara em pushes da branch `missao` do fork.
            // A `main` do fork espelha upstream — não vira imagem.
            when {
                anyOf {
                    branch 'missao'
                    expression { env.GIT_BRANCH == 'origin/missao' }
                }
            }
            steps {
                script {
                    def stackName = 'evolution-go'
                    def swarmFile = 'deploy/swarm.prod.yml'
                    def remoteFile = "/opt/stacks/${stackName}.yml"

                    sshagent(['swarm-deploy-key']) {
                        sh """
                          set -e

                          COMMIT=\$(git rev-parse --short HEAD)
                          echo "Deploying Evolution Go to Docker Swarm - Commit: \$COMMIT"

                          # Substitui :latest pela tag do commit no arquivo swarm
                          sed "s|:latest|:\$COMMIT|g" ${swarmFile} > ${swarmFile}.tmp

                          scp ${swarmFile}.tmp deploy@192.168.10.120:${remoteFile}
                          ssh deploy@192.168.10.120 \
                            docker stack deploy \
                              --with-registry-auth \
                              --resolve-image always \
                              -c ${remoteFile} \
                              ${stackName}

                          rm -f ${swarmFile}.tmp
                        """
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout ghcr.io || true'
            sh 'docker system prune -f || true'
        }
        success {
            echo '✅ Build, push e deploy concluídos'
        }
        failure {
            echo '❌ Pipeline falhou'
        }
    }
}
