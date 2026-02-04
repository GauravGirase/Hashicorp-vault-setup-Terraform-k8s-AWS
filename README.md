# Vault-Enabled Kubernetes: Integrating HashiCorp Vault with EKS


This project demonstrates the integration of HashiCorp Vault with Amazon Elastic Kubernetes Service (EKS) to provide secure, centralized secrets management for Kubernetes workloads. By connecting Vault to EKS, applications running in the cluster can dynamically retrieve credentials, API keys, and other sensitive data without hardcoding them into code or configuration files. The project covers configuring Vault authentication for Kubernetes, defining secrets policies, and automating secret injection into pods, ensuring enhanced security, compliance, and scalability for cloud-native applications.

## Features

- Centralized Secrets Management
--Store all sensitive data (API keys, database credentials, tokens) in HashiCorp Vault.
--Single source of truth for secrets across multiple EKS clusters.
- Dynamic Secrets Generation
--Vault can generate temporary, time-bound credentials for databases and cloud services.
--Eliminates the risk of long-lived static secrets.
- Kubernetes Native Authentication
--Use the Kubernetes Auth method to authenticate EKS pods with Vault.
--Ensures only authorized pods can access specific secrets.
- Automatic Secret Injection
--Inject secrets directly into pods using Vault Agent or CSI Secrets Store Driver.
--No need to hardcode credentials in manifests or environment variables.

## Installation
Install AWS CLI
```sh
sudo apt install -y unzip curl \
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
unzip awscliv2.zip \
sudo ./aws/install
```

Install terraform

```sh
sudo apt update \
sudo apt install -y gnupg software-properties-common curl \
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
| sudo tee /etc/apt/sources.list.d/hashicorp.list \
sudo apt update \
sudo apt install -y terraform
```
Create EKS cluster using terraform
```sh
git clone https://github.com/GauravGirase/Hashicorp-vault-setup-Terraform-k8s-AWS.git
cd terraform
terraform init
terraform plan
terraform apply
```
Install kubectl
```sh
curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl \
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version –client
```
Install eksctl (for creating a service account using cloudformation)
```sh
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" 
tar -xzf eksctl_Linux_amd64.tar.gz \
sudo mv eksctl /usr/local/bin/
eksctl version
```
Download & install Helm
``` sh
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```
Update kubeconfig for an EKS cluster
```sh
aws eks update-kubeconfig \
  --region <region> \
  --name <cluster-name>
```
Verify (Will list all the nodes)
```sh
kubectl get nodes
```
Enable IAM Roles for Service Accounts (IRSA) in your EKS cluster
```sh
eksctl utils associate-iam-oidc-provider \
  --cluster <cluster-name> \
  --region <region> \
  --approve
```
Create a service account with IAM role
integration (IRSA)
```sh
eksctl create iamserviceaccount \
-- region ap-south-1 \
-- name ebs-csi-controller-sa \
-- namespace kube-system \
-- cluster devopsshack-cluster \
-- attach-policy-arn arn:aws: iam :: aws:policy/service-role/AmazonEBSCSIDriverPolicy \
-- approve \
-- override-existing-serviceaccounts
```
Install AWS EBS CSI Driver
```sh
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-
driver/deploy/kubernetes/overlays/stable/ecr/?ref=release-1.11"
```
Install NGINX Ingress Controller
```sh
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-
nginx/main/deploy/static/provider/cloud/deploy.yaml
```
Install cert-manager
```sh
kubectl apply -f https://github.com/cert-manager/cert-
manager/releases/download/v1.12.0/cert-manager.yaml
```
## Vault setup
Create environment
```sh
kubectl create namespace vault
kubectl create serviceaccount vault-auth -n default
kubectl create serviceaccount vault-auth -n webapp
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -- namespace vault -- set "server.dev.enabled=true"
```
(Optional) Expose Vault with a LoadBalancer
```sh
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: vault
spec:
  type: LoadBalancer
  ports:
    - port: 8200
      targetPort: 8200
  selector:
    app.kubernetes.io/name: vault
```

## Configure Kubernetes Authentication in Vault (for default and webapp namespaces)
Enable Kubernetes Auth Method
```sh
kubectl exec -n vault -it vault-0 -- vault auth enable kubernetes
```
Configure the Kubernetes Auth Method: This command sets up Vault so that pods using the vault-auth service account (in the default namespace) can authenticate
```sh
kubectl exec -n vault -it vault-0 -- vault write auth/kubernetes/config \
token_reviewer_jwt="$(kubectl get secret -n kube-system $(kubectl get serviceaccount vault-auth -n default -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 -- decode)" \
kubernetes_host="$(kubectl config view -- raw -o=jsonpath='{.clusters[0].cluster.server}']" \
kubernetes_ca_cert="$(kubectl get secret -n kube-system $(kubectl get serviceaccount vault-auth -n default -o jsonpath="[.secrets[O].name]") -o isonpath="{.data['ca.crt']}" | base64 -- decode)"
```
For application namespace
```sh
kubectl exec -n vault -it vault-0 -- vault write auth/kubernetes/config \
token reviewer jwt="$(kubectl get secret -n kube-system $(kubectl get serviceaccount vault-auth -n webapps -o jsonpath="(.secrets[O].name}") -o jsonpath="{.data token}" | base64 -- decode)"\
kubernetes host="$(kubectl config view -- raw -o=jsonpath='( clusters[0].cluster server}']" \
kubernetes ca cert="S(kubectl get secret -n kube-system $(kubect get serviceaccount vault-auth -n webapps -o jsonpath="[.secrets[0].name]") -o jsonpath="{.data['ca.crt']}" | base64 -- decode)"
```
# Set Up Vault Policies and Roles
Create a Policy File (e.g., myapp-policy.hcl):
```sh
path "secret/data/mysql" {
capabilities = ["create", "update", "read", "delete", "list"]
	}
path "secret/data/frontend" {
capabilities = ["create", "update", "read", "delete", "list"]
}
```
## Note: In production grade we use read only capabilities
Apply the Policy in Vault
```sh
kubectl cp myapp-policy.hcl vault/vault-0:/tmp/myapp-policy.hcl
kubectl exec -n vault -it vault-0 -- vault policy write myapp-policy /tmp/myapp-policy.hcl
```
Create a Role to Bind the Service Account to the Policy
```sh
kubectl exec -n vault -it vault-0 -- vault write auth/kubernetes/role/vault-role \
bound_service_account_names=vault-auth \
bound_service_account_namespaces="default,webapps" \
policies=myapp-policy \
ttl=24h
```
Add Secrets to Vault
```sh
kubectl exec -n vault -it vault-0 -- vault kv put secret/mysql MYSQL_DATABASE=bankappdb
MYSQL_ROOT_PASSWORD=Test@123
```
Access secrets in running workloads
```sh
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: webapps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "mysql-role"
        vault.hashicorp.com/agent-inject-secret-mysql-creds: "secret/data/mysql"
    spec:
      serviceAccountName: vault-auth
      containers:
        - name: mysql
          image: mysql:8.0
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret  # populated by Vault
                  key: password
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
      volumes:
        - name: mysql-data
          persistentVolumeClaim:
            claimName: mysql-pvc
```
