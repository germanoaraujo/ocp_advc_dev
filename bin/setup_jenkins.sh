#!/bin/bash
# Setup Jenkins Project
if [ "$#" -ne 3 ]; then
    echo "Usage:"
    echo "  $0 GUID REPO CLUSTER"
    echo "  Example: $0 wkha https://github.com/redhat-gpte-devopsautomation/advdev_homework_template.git na311.openshift.opentlc.com"
    exit 1
fi

GUID=$1
REPO=$2
CLUSTER=$3
echo "Setting up Jenkins in project ${GUID}-jenkins from Git Repo ${REPO} for Cluster ${CLUSTER}"

# Set up Jenkins with sufficient resources
JENKINS_PROJECT_NAME="$GUID-jenkins"
echo "$JENKINS_PROJECT_NAME"
JENKINS_DISPLAY_NAME="$GUID-Persistent-Jenkins"
echo "$JENKINS_DISPLAY_NAME"

echo "Creating project: $JENKINS_PROJECT_NAME with Display Name: $JENKINS_DISPLAY_NAME"
oc new-project ${JENKINS_PROJECT_NAME} --display-name ${JENKINS_DISPLAY_NAME}
oc policy add-role-to-user edit system:serviceaccount:$JENKINS_PROJECT_NAME:jenkins -n $JENKINS_PROJECT_NAME

echo "** Creating Jenkins **"
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true

echo "** Adjust Jenkins settings **"
oc set resources dc jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m
oc label dc jenkins app=jenkins --overwrite
# TBD

# Create custom agent container image with skopeo
echo "** Creating Skopeo Jenkins Agent **"
oc new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
      USER root\nRUN yum -y install skopeo && yum clean all\n
      USER 1001' --name=jenkins-agent-appdev -n ${JENKINS_PROJECT_NAME}
# TBD

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
echo "** Creating Pipeline **"
oc new-build ${REPO} --context-dir="openshift-tasks"
# TBD

# Make sure that Jenkins is fully up and running before proceeding!
while : ; do
  echo "Checking if Jenkins is Ready..."
  AVAILABLE_REPLICAS=$(oc get dc jenkins -n ${GUID}-jenkins -o=jsonpath='{.status.availableReplicas}')
  if [[ "$AVAILABLE_REPLICAS" == "1" ]]; then
    echo "...Yes. Jenkins is ready."
    break
  fi
  echo "...no. Sleeping 10 seconds."
  sleep 10
done
