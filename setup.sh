#! /bin/bash

#sets environment variables
read -p 'GCP Region: ' REGION
export ZONE=$REGION-b
export NAME=terraria-world-1
export WORLD=worlds_World_1.wld
export COMPUTE_ENGINE_SA_EMAIL=$(gcloud iam service-accounts list --filter="name:Compute Engine default service account" --format "value(email)")
export REPO=terraria-world-1
export USERNAME=ammilam
#sets github specific environment variables to be used later
read -p 'GitHub Repo: ' REPO
read -p 'GitHub Username: ' USERNAME
read -sp 'GitHub Password: ' PASSWORD

cat <<EOF >>startup-script.yaml
kind: DaemonSet
apiVersion: extensions/v1beta1
metadata:
  name: startup-script
  namespace: kube-system
  labels:
    app: startup-script
spec:
  template:
    metadata:
      labels:
        app: startup-script
    spec:
      hostPID: true
      containers:
        - name: startup-script
          image: gcr.io/google-containers/startup-script:v1
          securityContext:
            privileged: true
          env:
          - name: STARTUP_SCRIPT
            value: |
              #! /bin/bash

              set -o errexit
              set -o pipefail
              set -o nounset
              sudo mkdir /tmp/world
              cd /tmp/world
              wget https://storage.googleapis.com/$DEVSHELL_PROJECT_ID-$REGION-$NAME/$WORLD
EOF

gsutil mb -b on gs://$DEVSHELL_PROJECT_ID-$REGION-$NAME
gsutil cp ./$WORLD gs://$DEVSHELL_PROJECT_ID-$REGION-$NAME/$WORLD
gsutil iam ch allUsers:objectViewer gs://$DEVSHELL_PROJECT_ID-$REGION-$NAME

#creates the k8s cluster in the sepcified region/zone and applies the startup-script daemonset
gcloud beta container --project $DEVSHELL_PROJECT_ID clusters create $NAME-$REGION --zone $ZONE  --image-type "UBUNTU" --scopes "https://www.googleapis.com/auth/cloud-platform" --metadata disable-legacy-endpoints=true
kubectl apply -f startup-script.yaml
rm startup-script.yaml

#creates the flux namespace and generates an ssh key
kubectl create namespace flux
ssh-keygen -t rsa -N '' -f ./flux/id_rsa -C flux <<< y
kubectl create secret generic flux-ssh --from-file=identity=./flux/id_rsa -n flux

#creates an executable to be invoked that creates a git deploy key on the repo specified above
cat <<EOF >>git-key-deploy.sh
#! /bin/bash
curl \
  -X POST \
  -u $USERNAME:$PASSWORD \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$USERNAME/$REPO/keys \
  -d '{"key":"$(cat ./flux/id_rsa.pub)","title":"flux-ssh"}'
EOF
sudo chmod +x git-key-deploy.sh
./git-key-deploy.sh
rm git-key-deploy.sh

#installs flux and helm operator that will kick off and manage the terraria server deployment
cd flux
./installFlux.sh
./installHelmOperator.sh