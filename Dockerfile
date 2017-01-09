FROM ubuntu:16.04

MAINTAINER Bo Wang "bo.wang@albumprinter.com"

RUN df -h 

RUN  echo "deb http://archive.ubuntu.com/ubuntu xenial main universe\n" > /etc/apt/sources.list \
  && echo "deb http://archive.ubuntu.com/ubuntu xenial-updates main universe\n" >> /etc/apt/sources.list \
  && echo "deb http://security.ubuntu.com/ubuntu xenial-security main universe\n" >> /etc/apt/sources.list

RUN apt-get update -qqy \
  && apt-get -qqy --no-install-recommends install software-properties-common \
  && add-apt-repository -y ppa:git-core/ppa
RUN df -h 
#========================
# Miscellaneous packages
# iproute which is surprisingly not available in ubuntu:15.04 but is available in ubuntu:latest
# OpenJDK8
# rlwrap is for azure-cli
# groff is for aws-cli
# tree is convenient for troubleshooting builds
#========================
RUN apt-get update -qqy \
  && apt-get -qqy --no-install-recommends install \
    iproute \
    openssh-client ssh-askpass\
    ca-certificates \
    openjdk-8-jdk \
    tar zip unzip \
    wget curl \
    git \
    build-essential \
    less nano tree \
    python python-pip groff \
    python-setuptools\
    rlwrap \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i 's/securerandom\.source=file:\/dev\/random/securerandom\.source=file:\/dev\/urandom/' ./usr/lib/jvm/java-8-openjdk-amd64/jre/lib/security/java.security

# workaround https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=775775
RUN [ -f "/etc/ssl/certs/java/cacerts" ] || /var/lib/dpkg/info/ca-certificates-java.postinst configure
RUN apt-get autoclean
RUN apt-get autoremove
RUN apt-get clean
RUN df -h 
#==========
# Maven
#==========
ENV MAVEN_VERSION 3.3.9

RUN curl -fsSL http://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar xzf - -C /usr/share \
  && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn

ENV MAVEN_HOME /usr/share/maven
RUN df -h 
#==========
# Ant
#==========
RUN curl -fsSL https://www.apache.org/dist/ant/binaries/apache-ant-1.10.0-bin.tar.gz | tar xzf - -C /usr/share \
  && mv /usr/share/apache-ant-1.10.0 /usr/share/ant \
  && ln -s /usr/share/ant/bin/ant /usr/bin/ant

ENV ANT_HOME /usr/share/ant
RUN df -h 
#========================================
# Add normal user with passwordless sudo
#========================================
RUN useradd jenkins --shell /bin/bash --create-home \
  && usermod -a -G sudo jenkins \
  && echo 'ALL ALL = (ALL) NOPASSWD: ALL' >> /etc/sudoers \
  && echo 'jenkins:secret' | chpasswd
RUN df -h 
#====================================
# Cloud Foundry CLI
# https://github.com/cloudfoundry/cli
#====================================
RUN pip install --upgrade pip
RUN wget -O - "http://cli.run.pivotal.io/stable?release=linux64-binary&source=github" | tar -C /usr/local/bin -zxf -
RUN df -h 
#====================================
# AWS CLI
#====================================
RUN pip install awscli

RUN df -h

# compatibility with CloudBees AWS CLI Plugin which expects pip to be installed as user
RUN mkdir -p /home/jenkins/.local/bin/ \
  && ln -s /usr/bin/pip /home/jenkins/.local/bin/pip \
  && chown -R jenkins:jenkins /home/jenkins/.local

#====================================
# NODE JS
# See https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions
#====================================
RUN curl -sL https://deb.nodesource.com/setup_4.x | bash \
    && apt-get install -y nodejs

#====================================
# AZURE CLI
# See https://hub.docker.com/r/microsoft/azure-cli/~/dockerfile/
#====================================

RUN npm install --global azure-cli@0.10.1

#====================================
# BOWER, GRUNT, GULP
#====================================

RUN npm install --global grunt-cli@0.1.2 bower@1.7.9 gulp@3.9.1

#====================================
# Kubernetes CLI
# See http://kubernetes.io/v1.0/docs/getting-started-guides/aws/kubectl.html
#====================================
RUN curl https://storage.googleapis.com/kubernetes-release/release/v1.2.3/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

#====================================
# OPENSHIFT V3 CLI
# Only install "oc" executable, don't install "openshift", "oadmin"...
#====================================
RUN mkdir /var/tmp/openshift \
      && wget -O - "https://github.com/openshift/origin/releases/download/v1.2.0/openshift-origin-client-tools-v1.2.0-2e62fab-linux-64bit.tar.gz" \
      | tar -C /var/tmp/openshift --strip-components=1 -zxf - \
      && mv /var/tmp/openshift/oc /usr/local/bin \
      && rm -rf /var/tmp/openshift

#====================================
# Clone product and install java depedencies
# https://github.com/albumprinter/FitNesseTestFramework.git
#====================================

# Make ssh dir
RUN mkdir /root/.ssh/

# Copy over private key, and set permissions
ADD id_rsa /root/.ssh/id_rsa
RUN chmod 600 /root/.ssh/id_rsa

# Create known_hosts
RUN touch /root/.ssh/known_hosts
# Add bitbuckets key
RUN ssh-keyscan github.com >> /root/.ssh/known_hosts

# Clone the conf files into the docker container
RUN git clone git@github.com:albumprinter/FitNesseTestFramework.git /root/repo

RUN cd /root/repo && mvn install -Dmaven.test.skip=true
RUN rm -rf /root/repo

#====================================
# Install Jars
# serenity-core-1.1.42.jar
#====================================
COPY serenity-core-1.1.42.jar /usr/local/serenity-core-1.1.42.jar
RUN  mvn install:install-file -Dfile=/usr/local/serenity-core-1.1.42.jar -DgroupId=net.serenity-bdd -DartifactId=serenity-core -Dversion=1.1.42 -Dpackaging=jar

#====================================
# Copy dependencies to jenkins user
# 
#====================================
RUN cp -a /root/.m2 /home/jenkins/.m2
RUN echo Display jenkins m2 size
RUN du -hs /home/jenkins/.m2
RUN chown -R jenkins /home/jenkins/.m2
RUN rm -rf /root/.m2

#====================================
# Setup Jenkins Slave
# 
#====================================

USER root

ARG VERSION=2.62

RUN curl --create-dirs -sSLo /usr/share/jenkins/slave.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${VERSION}/remoting-${VERSION}.jar \
  && chmod 755 /usr/share/jenkins \
  && chmod 644 /usr/share/jenkins/slave.jar

COPY jenkins-slave /usr/local/bin/jenkins-slave

RUN chmod a+rwx /home/jenkins
WORKDIR /home/jenkins
USER jenkins

ENTRYPOINT ["/usr/local/bin/jenkins-slave"]
