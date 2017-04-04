# Higginbotham

### Develop Locally

1. Start the Postgres Database Container

    `docker run -e "POSTGRES_USER=higginbotham" -e "POSTGRES_PASSWORD=higginbotham" -p 5432:5432 postgres:9.6.1`

2. Start the service

    `./higginbothamservice/gradlew bootRun` 
     
3. Browse to service API address

    `http://localhost:8080`
    
4. In 'higginbothamservice/gradle.properties' set the 'projectGroup' variable to your own docker hub id

    `projectGroup=myDockerHubId`
    
5. In 'docker/docker-compose.yml' set the 'services.web.image' property to include your own docker hub id

    `image: myDockerHubId/higginbotham`

6. Rebuild web container with your local changes and push to your Docker Hub repo

    `./higginbothamservice/gradlew build buildDocker`
    
### Deploy Containerised Application Locally

1. Browse to the 'environment' directory and issue the command:

    `docker-compose up`

2. Browse to service API address

    `http://localhost:8080`

### Deploy Containerised Application to your AWS Account

Prerequisites:
  * AWS Account
  * AWS CLI
  * AWS EC2 Key Pair

1. Browse to the 'environment' directory and issue the command:

    `./higginbothamservice/gradlew deployToAws -Pkey=/your/aws/key/pair/location/aws-key-pair-name.pem`

The script will deploy two CloudFormation scripts.  The first script will create a VPC network
and the second will create the EC2 Instance.  Once the EC2 instance has been created the latest
updates will be downloaded and installed.  The EC2 instance will then be rebooted to apply the updates.
Once the instance restarts the 'docker-compose' file will be downloaded and run.  The script will finish
when the Higginbotham service is running and it will print the address the service can be accessed to
the terminal output.
