#! /bin/bash

#sets environment variables
read -p 'GCP Region: ' REGION
export ZONE=$REGION-b
export NAME=terraria-world-1
#sets github specific environment variables to be used later
read -p 'GitHub Repo: ' REPO
read -p 'GitHub Username: ' USERNAME
read -sp 'GitHub Password: ' PASSWORD

#creates the k8s cluster in the sepcified region/zone and applies the startup-script daemonset
gcloud container --project $DEVSHELL_PROJECT_ID clusters create $NAME-$REGION --zone $ZONE

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
rm id_rsa
rm id_rsa.pub