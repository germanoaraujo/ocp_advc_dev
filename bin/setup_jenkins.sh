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

# Create Tasks Dev Project
TASKS_DEV_PROJECT_NAME="$GUID-tasks-dev"
echo "$TASKS_DEV_PROJECT_NAME"
echo "Creating project: $TASKS_DEV_PROJECT_NAME with Display Name: $TASKS_DEV_PROJECT_NAME"
oc new-project ${TASKS_DEV_PROJECT_NAME} --display-name ${TASKS_DEV_PROJECT_NAME}

# Set up Dev Application
oc new-build --binary=true --name="tasks" jboss-eap71-openshift:1.4 -n $TASKS_DEV_PROJECT_NAME
oc new-app $TASKS_DEV_PROJECT_NAME/tasks:0.0-0 --name=tasks --allow-missing-imagestream-tags=true -n $TASKS_DEV_PROJECT_NAME
oc set triggers dc/tasks --remove-all -n $TASKS_DEV_PROJECT_NAME
oc expose dc tasks --port 8080 -n $TASKS_DEV_PROJECT_NAME
oc expose svc tasks -n $TASKS_DEV_PROJECT_NAME
oc set probe dc/tasks -n $TASKS_DEV_PROJECT_NAME --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/
oc create configmap tasks-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n $TASKS_DEV_PROJECT_NAME
oc set volume dc/tasks --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-config -n $TASKS_DEV_PROJECT_NAME
oc set volume dc/tasks --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-config -n $TASKS_DEV_PROJECT_NAME

# Create Tasks PROD Project
TASKS_PROD_PROJECT_NAME="$GUID-tasks-prod"
echo "$TASKS_PROD_PROJECT_NAME"
echo "Creating project: $TASKS_PROD_PROJECT_NAME with Display Name: $TASKS_PROD_PROJECT_NAME"
oc new-project ${TASKS_PROD_PROJECT_NAME} --display-name ${TASKS_PROD_PROJECT_NAME}

# Create Blue Application
oc new-app ${GUID}-tasks-dev/tasks:0.0 --name=tasks-blue --allow-missing-imagestream-tags=true -n ${GUID}-tasks-prod
oc set triggers dc/tasks-blue --remove-all -n ${GUID}-tasks-prod
oc expose dc tasks-blue --port 8080 -n ${GUID}-tasks-prod
oc set probe dc tasks-blue -n ${GUID}-tasks-prod --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/
oc create configmap tasks-blue-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n ${GUID}-tasks-prod
oc set volume dc/tasks-blue --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-blue-config -n ${GUID}-tasks-prod
oc set volume dc/tasks-blue --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-blue-config -n ${GUID}-tasks-prod

# Create Green Application
oc new-app ${GUID}-tasks-dev/tasks:0.0 --name=tasks-green --allow-missing-imagestream-tags=true -n ${GUID}-tasks-prod
oc set triggers dc/tasks-green --remove-all -n ${GUID}-tasks-prod
oc expose dc tasks-green --port 8080 -n ${GUID}-tasks-prod
oc set probe dc tasks-green -n ${GUID}-tasks-prod --readiness --failure-threshold 3 --initial-delay-seconds 60 --get-url=http://:8080/
oc create configmap tasks-green-config --from-literal="application-users.properties=Placeholder" --from-literal="application-roles.properties=Placeholder" -n ${GUID}-tasks-prod
oc set volume dc/tasks-green --add --name=jboss-config --mount-path=/opt/eap/standalone/configuration/application-users.properties --sub-path=application-users.properties --configmap-name=tasks-green-config -n ${GUID}-tasks-prod
oc set volume dc/tasks-green --add --name=jboss-config1 --mount-path=/opt/eap/standalone/configuration/application-roles.properties --sub-path=application-roles.properties --configmap-name=tasks-green-config -n ${GUID}-tasks-prod

# Expose Blue service as route to make blue application active
oc expose svc/tasks-blue --name tasks -n ${GUID}-tasks-prod

# Create Jenkins Project
JENKINS_PROJECT_NAME="$GUID-jenkins"
echo "$JENKINS_PROJECT_NAME"
JENKINS_DISPLAY_NAME="$GUID-Persistent-Jenkins"
echo "$JENKINS_DISPLAY_NAME"
echo "Creating project: $JENKINS_PROJECT_NAME with Display Name: $JENKINS_DISPLAY_NAME"
oc new-project ${JENKINS_PROJECT_NAME} --display-name ${JENKINS_DISPLAY_NAME}

# Deploy Persistent Jenkins
echo "** Deploy Jenkins App **"
oc new-app jenkins-persistent --param ENABLE_OAUTH=true --param MEMORY_LIMIT=2Gi --param VOLUME_CAPACITY=4Gi --param DISABLE_ADMINISTRATIVE_MONITORS=true

# Adjust Jenkins Resource Resource
echo "** Adjust Jenkins Resource Resource **"
oc set resources dc jenkins --limits=memory=2Gi,cpu=2 --requests=memory=1Gi,cpu=500m
oc label dc jenkins app=jenkins --overwrite

# Configure Jenkins Service Accounts
echo "** Configure Jenkins Service Accounts **"
oc policy add-role-to-group edit system:serviceaccounts:$JENKINS_PROJECT_NAME -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-group edit system:serviceaccounts:$JENKINS_PROJECT_NAME -n $TASKS_PROD_PROJECT_NAME
oc policy add-role-to-group system:image-puller system:serviceaccounts:$TASKS_PROD_PROJECT_NAME -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:$JENKINS_PROJECT_NAME:jenkins -n $TASKS_DEV_PROJECT_NAME
oc policy add-role-to-user edit system:serviceaccount:$JENKINS_PROJECT_NAME:jenkins -n $TASKS_PROD_PROJECT_NAME

# Create pipeline build config pointing to the ${REPO} with contextDir `openshift-tasks`
echo "** Creating Pipeline Build Config **"
PIPELINE_STRATEGY="pipeline"
PIPELINE_CONTEXT_PATH="openshift-tasks"
echo "Creating Pipeline with repo ${REPO} strategy ${PIPELINE_STRATEGY} and context-dir ${PIPELINE_CONTEXT_PATH}"
oc new-build ${REPO} --strategy=${PIPELINE_STRATEGY} --context-dir=${PIPELINE_CONTEXT_PATH}

# Create custom agent container image with skopeo
echo "** Creating Skopeo Jenkins Agent **"
oc new-build -D $'FROM docker.io/openshift/jenkins-agent-maven-35-centos7:v3.11\n
      USER root\nRUN yum -y install skopeo && yum clean all\n
      USER 1001' --name=jenkins-agent-appdev -n $JENKINS_PROJECT_NAME

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
