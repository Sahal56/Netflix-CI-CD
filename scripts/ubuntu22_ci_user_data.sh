#!/bin/bash

# This Script installs Java, Jenkins, Docker, Trivy & SonarQube Server container, Nginx, Certbot.
# It setups domain name via reverse proxy & Https
# It has been tested on AWS on Ubuntu 22.04

# Variables
USER="ubuntu"

# Update Packages
sudo apt-get update -y

# Install Java
sudo apt install -y fontconfig openjdk-17-jre

# Install Jenkins
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update && apt-get install jenkins -y
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Install Docker
sudo apt-get update && apt-get install docker.io -y
sudo usermod -aG docker $USER
sudo usermod -aG docker jenkins # Add Jenkins user to Docker group
newgrp docker # Applies the docker group permissions immediately
sudo chmod 777 /var/run/docker.sock

# Install trivy
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update && apt-get install trivy -y

# Install & Run SonarQube as Container
docker run -d --name sonar -p 9000:9000 sonarqube:lts-community

# Install Nginx & certbot for https
apt install -y nginx certbot python3-certbot-nginx

setup_nginx_and_certbot() {
  local domain=$1
  local port=$2

  echo "Setting up Nginx for $domain -> localhost:$port"

  cat <<EOF > /etc/nginx/sites-available/$domain
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
}

DOMAIN_ROOT="sahalpathan.live"
DOMAIN_JENKINS="jenkins.${DOMAIN_ROOT}"
DOMAIN_SONARQUBE="sonarqube.${DOMAIN_ROOT}"
DOMAIN_NETFLIX_TEST="netflixtest.${DOMAIN_ROOT}"

setup_nginx_and_certbot $DOMAIN_JENKINS 8080
setup_nginx_and_certbot $DOMAIN_SONARQUBE 9000

nginx -t && systemctl reload nginx
certbot --nginx -d ${DOMAIN_JENKINS} -d ${DOMAIN_SONARQUBE} \
  --non-interactive --agree-tos --register-unsafely-without-email