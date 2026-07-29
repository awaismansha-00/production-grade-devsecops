# Project Runbook

This runbook explains how to run and verify the project step by step. Each phase has a checkpoint. Do not move to the next phase until the current phase and all previous phases are working.

The app is a React frontend served by an Express backend. The backend connects to MySQL during startup and creates the `users` table if it does not already exist. For local testing, Docker Compose starts both MySQL and the app together.

All commands are for you to run manually from your terminal.

## End-To-End Order

Use this order to run the whole project successfully:

1. Verify tools in Phase 1.
2. Run the app locally with Docker Compose in Phase 2.
3. Export all Terraform credentials in Phase 3.2, including RDS, QA/prod DB, and Grafana credentials.
4. Review ingress/domain notes in Phase 3.5. The first cloud run uses HTTP through the ALB DNS name.
5. Create the Terraform backend in Phase 4.1 and capture `BACKEND_BUCKET`.
6. Provision AWS infrastructure in Phase 4.2.
7. Bootstrap MySQL and create AWS Secrets Manager values in Phase 5.
8. Build and push a fresh app image in Phase 6. This is required for `/metrics`, structured logs, and Jaeger tracing to exist in the cloud app.
9. Deploy Argo CD and applications in Phase 7.
10. Verify app, Grafana, Prometheus, EFK, and Jaeger in Phase 7 before considering the deployment complete.

## Phase 1: Verify Prerequisites

Run these from the repository root:

```bash
docker --version
docker compose version
```

Expected result:

- Docker is installed and running.
- Docker Compose is available through `docker compose`.

Cloud deployment tools:

```bash
aws --version
terraform version
kubectl version --client
helm version
```

Expected result:

- AWS CLI is installed.
- Terraform is installed.
- kubectl is installed.
- Helm is installed.

Optional local debugging tools:

```bash
node -v
npm -v
```

Troubleshooting:

- If Docker is missing, install Docker Desktop or Docker Engine.
- If Docker says the daemon is not running, start Docker and retry.
- If `docker compose` is missing, install a Docker version that includes Compose v2.
- If AWS, Terraform, kubectl, or Helm are missing, install them before cloud deployment.

## Phase 2: Run Locally With Docker Compose

From the repository root, start the full local stack:

```bash
docker compose up --build
```

What this starts:

- `mysql`: MySQL 8.0 with a persistent Docker volume.
- `app`: the Node.js app built from the root `Dockerfile`.
- React frontend build happens inside the Docker image.
- Express serves both the API and frontend on port `5000`.

Local service details:

```text
Application URL: http://localhost:5000
API URL:         http://localhost:5000/api/users
MySQL host port: localhost:3307
MySQL container: mysql:3306
Database:        test_db
User:            appuser
Password:        password123
```

Expected app logs:

```text
Database connected and users table initialized or already exists.
Server is running on http://localhost:5000
```

Keep `docker compose up --build` running. In a second terminal, verify the API:

```bash
curl http://localhost:5000/api/users
```

Expected result on a fresh database:

```json
[]
```

Create a test user:

```bash
curl -X POST http://localhost:5000/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com","role":"Admin"}'
```

Verify the user is stored:

```bash
curl http://localhost:5000/api/users
```

Verify Prometheus metrics locally:

```bash
curl http://localhost:5000/metrics
```

Expected result:

- Metrics include `http_requests_total`.
- Metrics include `http_request_duration_seconds`.
- Metrics include Node.js process metrics.

Open the frontend:

```text
http://localhost:5000
```

Expected result:

- The browser shows the User Management App.
- Adding a user in the browser updates the list.
- The API still responds at `/api/users`.

Stop the local stack:

```bash
docker compose down
```

Stop the stack and delete the MySQL data volume:

```bash
docker compose down -v
```

Use `docker compose down -v` only when you want a fresh database next time.

Troubleshooting:

- If port `5000` is already in use, stop the other process or change the app port mapping in `docker-compose.yml`.
- If port `3307` is already in use, change the MySQL host port mapping in `docker-compose.yml`; the app container still uses `DB_HOST=mysql` internally.
- If the app cannot connect to MySQL, check service health and logs:

```bash
docker compose ps
docker compose logs mysql
docker compose logs app
```

- If MySQL is unhealthy, wait a little longer, then rerun `docker compose ps`.
- If the app exits before MySQL is ready, run `docker compose up --build` again after MySQL becomes healthy.
- If the app logs `ER_NOT_SUPPORTED_AUTH_MODE`, reset the local MySQL volume once, then start again:

```bash
docker compose down -v
docker compose up --build
```

- If `docker compose up --build` fails during `npm ci`, confirm your internet connection and npm registry access.
- If the frontend does not look updated, rebuild without cache:

```bash
docker compose build --no-cache app
docker compose up
```

## Phase 3: Prepare For Cloud Deployment

Only start this phase after the local Docker Compose stack works.

### 3.1 Confirm AWS Identity

Run:

```bash
aws sts get-caller-identity
```

Expected result:

- AWS returns your account ID, user/role ARN, and user ID.
- The account is the one where you want to create EKS, ECR, RDS, Secrets Manager, and S3 resources.

Troubleshooting:

- If this fails, run `aws configure` or refresh your SSO/login session.
- If the account is wrong, switch AWS profiles before continuing.

### 3.2 Choose And Export Terraform Password Inputs

Terraform does not randomly generate these passwords. You choose them, export them, and Terraform uses those exact values.

Choose strong values locally:

```bash
export TF_VAR_rds_master_username='adminuser'
export TF_VAR_rds_master_password='replace-with-strong-master-password'
export TF_VAR_qa_db_password='replace-with-strong-qa-password'
export TF_VAR_prod_db_password='replace-with-strong-prod-password'
export TF_VAR_grafana_admin_username='admin'
export TF_VAR_grafana_admin_password='replace-with-strong-grafana-password'
```

RDS master password rules:

- Use 8-41 characters.
- Use printable ASCII characters.
- Do not use `/`, `@`, double quote, or spaces.

What these become:

```text
TF_VAR_rds_master_username -> RDS master username
TF_VAR_rds_master_password -> RDS master password
TF_VAR_qa_db_password      -> QA app database user password
TF_VAR_prod_db_password    -> Production app database user password
TF_VAR_grafana_admin_username -> Grafana admin username
TF_VAR_grafana_admin_password -> Grafana admin password
```

Defaults already in Terraform:

```text
qa_db_name       = qa_app_db
qa_db_username   = qa_app_user
prod_db_name     = prod_app_db
prod_db_username = prod_app_user
```

Verify the values are set in your current terminal:

```bash
printenv TF_VAR_rds_master_username
printenv TF_VAR_rds_master_password
printenv TF_VAR_qa_db_password
printenv TF_VAR_prod_db_password
printenv TF_VAR_grafana_admin_username
printenv TF_VAR_grafana_admin_password
```

Expected result:

- Each command prints a value.
- Do not paste these values into Git, screenshots, tickets, or chat.

Important:

- These environment variables only exist in the current terminal session.
- If you open a new terminal, export them again.
- Do not commit passwords in `.tfvars`, `.env`, README files, or shell history snippets.

### 3.3 Understand Which AWS Secrets Are Created Automatically

Do not manually create these app secrets if you are following this Terraform flow:

```text
qa/mysql_secret
prod/mysql_secret
monitoring/grafana_secret
```

Terraform creates the secret containers during the first infrastructure apply.

Terraform writes the Grafana secret from your exported values during the first infrastructure apply:

```text
GRAFANA_USERNAME
GRAFANA_PASSWORD
```

Terraform writes secret values only after MySQL bootstrap is enabled:

```bash
terraform apply -var='enable_mysql_bootstrap=true'
```

The AWS Secrets Manager values will contain:

```text
DB_HOST
DB_NAME
DB_USER
DB_PASSWORD
DATABASE_URL
```

Kubernetes External Secrets reads those AWS secrets and creates Kubernetes secrets named:

```text
qa/mysql-secret
prod/mysql-secret
monitoring/grafana-admin-secret
```

The app pods read database environment variables from the MySQL Kubernetes secrets. Grafana reads its admin credentials from `monitoring/grafana-admin-secret`.

### 3.4 Understand The Terraform Backend Bucket Name

Terraform creates the remote state S3 bucket for you and adds a generated suffix so the name is globally unique.

```text
production-grade-devsecops-state-<random-hex>
```

The suffix is generated by Terraform once and then stays stable in Terraform state.

Important:

- You do not need to manually choose a bucket name.
- You do not need to check whether the fixed old name is available.
- After the backend bucket is created, capture the generated name and pass it to the production Terraform init step.

### 3.5 Understand App Ingress, Domain, And TLS

The first cloud deployment does not require a custom domain or ACM certificate.

By default, the app ingress files are configured for HTTP through the AWS ALB DNS name:

```text
k8s/qa/app-ingress.yaml
k8s/prod/app-ingress.yaml
```

After deployment, get the ALB address:

```bash
kubectl get ingress -n qa
kubectl get ingress -n prod
```

Open the `ADDRESS` value in your browser with `http://`.

For custom domain and TLS later, edit the same ingress files and uncomment the saved example lines for:

```text
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
alb.ingress.kubernetes.io/ssl-redirect: '443'
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:eu-west-2:123456789012:certificate/...
host: myapp.example.com
```

Before uncommenting them, replace the examples with:

```text
your real domain or subdomain
your real ACM certificate ARN from eu-west-2
```

For an ALB in `eu-west-2`, the ACM certificate should be in `eu-west-2`.

Verify certificate:

```bash
aws acm list-certificates --region eu-west-2
```

Expected result:

- Your certificate appears.
- Certificate status is `ISSUED`.

DNS note:

- After Kubernetes creates the ALB, create a DNS record pointing your domain to the ALB DNS name.
- In Route 53, use an alias record when possible.

Monitoring note:

- Grafana public ingress is disabled by default in `k8s/observability/values/kube-prometheus-stack-values.yaml`.
- Use port-forward first. Add a public Grafana domain and TLS later by enabling and replacing the commented ingress placeholders.

### 3.6 Prepare Container Image Flow

The Kubernetes deployment files currently contain placeholder ECR images:

```text
123456789012.dkr.ecr.eu-west-2.amazonaws.com/nodejs-app:latest
```

You have two options:

1. Let GitHub Actions build and push the image, then update the QA manifest.
2. Manually build and push an image to the Terraform-created ECR repository, then update the manifest yourself.

If using GitHub Actions, set these repository variables:

```text
AWS_REGION=eu-west-2
ECR_REPOSITORY=nodejs-app
```

Set these repository secrets:

```text
AWS_ROLE_TO_ASSUME
SONAR_TOKEN
SONAR_HOST_URL
```

`AWS_ROLE_TO_ASSUME` is available after Terraform creates the GitHub Actions role:

```bash
terraform output github_actions_ecr_role_arn
```

If you are not using SonarQube yet, expect the QA workflow to fail at the SonarQube stage until those values are configured or the workflow is adjusted.

### 3.7 Watch For MySQL Authentication Compatibility

The app currently uses the older Node `mysql` package.

Local Docker Compose uses `mysql_native_password` compatibility. In AWS RDS MySQL 8.0, if the app logs this error:

```text
ER_NOT_SUPPORTED_AUTH_MODE
```

Use one of these fixes:

- Preferred app fix: migrate the backend dependency from `mysql` to `mysql2`.
- Infrastructure/user fix: ensure app DB users use `mysql_native_password`.

Do not continue debugging Kubernetes until the database auth issue is resolved.

## Phase 4: Deploy AWS Infrastructure

This phase creates cloud resources and can incur cost.

### 4.1 Create Terraform Remote State Backend

From the repository root:

```bash
cd terraform/backend
terraform init
terraform plan
terraform apply
```

Verify:

```bash
terraform output
BACKEND_BUCKET="$(terraform output -raw s3_bucket_name)"
echo "$BACKEND_BUCKET"
```

Expected result:

- Backend resources are created successfully.
- Terraform outputs show a bucket name like `production-grade-devsecops-state-<random-hex>`.
- `BACKEND_BUCKET` contains that generated bucket name.

Troubleshooting:

- If `terraform init` fails, confirm AWS credentials and provider download access.
- If bucket creation still fails because the generated name is taken, rerun only after understanding whether Terraform state already exists; the suffix is designed to make this very unlikely.
- If permissions fail, confirm your AWS identity can create the configured backend resources.
- If you open a new terminal later, return to `terraform/backend` and run `BACKEND_BUCKET="$(terraform output -raw s3_bucket_name)"` again.

### 4.2 Provision Infrastructure Without MySQL Bootstrap

From the backend folder:

```bash
cd ../environments/prod
terraform init -backend-config="bucket=${BACKEND_BUCKET}"
terraform plan \
  -var='enable_mysql_bootstrap=false' \
  -var='enable_nat_gateway=false' \
  -var='eks_nodes_in_public_subnets=true'
terraform apply \
  -var='enable_mysql_bootstrap=false' \
  -var='enable_nat_gateway=false' \
  -var='eks_nodes_in_public_subnets=true'
```

This first-run networking mode avoids NAT gateways and Elastic IPs. It is intended for AWS accounts where EIP allocation is blocked. EKS worker nodes and the SSM tunnel host run in public subnets, while RDS remains in private subnets.

Verify Terraform outputs:

```bash
terraform output
```

Expected result:

- VPC, EKS, ECR, RDS, AWS Load Balancer Controller, External Secrets Operator, SSM tunnel host, and GitHub Actions ECR role are created.
- Outputs include `cluster_name`, `nodejs_app_ecr_repository_url`, `rds_mysql_address`, `ssm_tunnel_instance_id`, and `github_actions_ecr_role_arn`.

Configure kubectl:

```bash
aws eks update-kubeconfig --region eu-west-2 --name "$(terraform output -raw cluster_name)"
kubectl get nodes
```

Expected result:

- kubectl can see EKS nodes.

Troubleshooting:

- If provider initialization fails, rerun `terraform init` after checking AWS credentials and internet access.
- If Terraform says the backend bucket is missing, confirm `BACKEND_BUCKET` is set with `echo "$BACKEND_BUCKET"` and rerun `terraform init -backend-config="bucket=${BACKEND_BUCKET}"`.
- If Terraform reports missing variables, confirm all `TF_VAR_*` values from Phase 3.2 are exported in this terminal.
- If EIP allocation is blocked, keep `enable_nat_gateway=false`.
- If EKS nodes fail to join, confirm `eks_nodes_in_public_subnets=true` and that public subnets have `map_public_ip_on_launch`.
- If EKS nodes do not appear, wait for node groups to finish creating and check the AWS console.
- If `kubectl get nodes` is unauthorized, refresh kubeconfig and confirm your AWS identity has cluster access.
- If AWS Load Balancer Controller failed and blocks other Helm releases with `no endpoints available for service "aws-load-balancer-webhook-service"`, clean the failed release and webhook objects, then rerun Terraform:

```bash
helm uninstall aws-load-balancer-controller -n kube-system || true
kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found
kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook --ignore-not-found
terraform apply \
  -var='enable_mysql_bootstrap=false' \
  -var='enable_nat_gateway=false' \
  -var='eks_nodes_in_public_subnets=true'
```

- If `aws-ebs-csi-driver` is stuck creating, inspect it:

```bash
aws eks describe-addon --region eu-west-2 --cluster-name "$(terraform output -raw cluster_name)" --addon-name aws-ebs-csi-driver
kubectl get pods -n kube-system | grep ebs
kubectl get events -n kube-system --sort-by=.lastTimestamp | tail -30
```

- If the add-on was created during the temporary optional-EBS flow, Terraform will migrate the state from indexed resources to normal resources using the committed `moved` blocks. This should not recreate the add-on.
- If Terraform reports an EBS CSI resource already exists outside state, import the exact resource it names instead of deleting working cluster resources.

## Phase 5: Bootstrap MySQL And Create App Secrets

This phase creates QA/prod databases, QA/prod database users, and writes app DB secrets to AWS Secrets Manager.

Start an SSM tunnel to private RDS:

```bash
aws ssm start-session \
  --target "$(terraform output -raw ssm_tunnel_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(terraform output -raw rds_mysql_address)\"],\"portNumber\":[\"3306\"],\"localPortNumber\":[\"3307\"]}"
```

Keep that SSM session running.

In another terminal, go to the Terraform environment folder and export the same password variables again:

```bash
cd terraform/environments/prod
export TF_VAR_rds_master_username='adminuser'
export TF_VAR_rds_master_password='replace-with-strong-master-password'
export TF_VAR_qa_db_password='replace-with-strong-qa-password'
export TF_VAR_prod_db_password='replace-with-strong-prod-password'
export TF_VAR_grafana_admin_username='admin'
export TF_VAR_grafana_admin_password='replace-with-strong-grafana-password'
```

Enable MySQL bootstrap:

```bash
terraform plan -var='enable_mysql_bootstrap=true'
terraform apply -var='enable_mysql_bootstrap=true'
```

Verify AWS Secrets Manager:

```bash
aws secretsmanager describe-secret --region eu-west-2 --secret-id qa/mysql_secret
aws secretsmanager describe-secret --region eu-west-2 --secret-id prod/mysql_secret
aws secretsmanager describe-secret --region eu-west-2 --secret-id monitoring/grafana_secret
aws secretsmanager get-secret-value --region eu-west-2 --secret-id monitoring/grafana_secret --query SecretString --output text
```

Expected result:

- QA MySQL, prod MySQL, and Grafana secrets exist.
- Grafana has a secret version from the infrastructure apply.
- QA and prod MySQL secrets have versions after bootstrap.
- The Grafana secret contains `GRAFANA_USERNAME` and `GRAFANA_PASSWORD`.
- Do not share the `get-secret-value` output because it contains the Grafana password.

Troubleshooting:

- If SSM session fails, confirm the tunnel instance exists, has SSM permissions, and can reach RDS.
- If local port `3307` is in use, choose another local port and update the MySQL provider endpoint in Terraform before applying.
- If bootstrap cannot connect, confirm RDS security groups allow access from the tunnel host.
- If Terraform asks for variables again, export the `TF_VAR_*` values in that terminal.

## Phase 6: Configure CI/CD Or Push An Image

The Kubernetes app cannot run until the deployment image points to a real ECR image.

Important:

- Build and push a fresh image after these observability changes.
- Old images will not expose `/metrics`.
- Old images will not emit structured request logs.
- Old images will not send traces to Jaeger.

### Option A: Use GitHub Actions

In GitHub repository settings, create repository variables:

```text
AWS_REGION=eu-west-2
ECR_REPOSITORY=nodejs-app
```

Create repository secrets:

```text
AWS_ROLE_TO_ASSUME=<value from terraform output github_actions_ecr_role_arn>
SONAR_TOKEN=<your SonarQube token>
SONAR_HOST_URL=<your SonarQube URL>
```

Push application changes to the `qa` branch so the QA workflow builds and pushes an image.

Expected result:

- ECR contains `nodejs-app:<git-sha>` and `nodejs-app:latest`.
- `k8s/qa/app-deployment.yaml` on the `qa` branch is updated with the SHA image.

### Option B: Manually Build And Push

Get the ECR repository URL:

```bash
terraform output -raw nodejs_app_ecr_repository_url
```

Authenticate Docker to ECR:

```bash
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin "$(terraform output -raw nodejs_app_ecr_repository_url | cut -d/ -f1)"
```

Build, tag, and push:

```bash
docker build -t nodejs-app:manual .
docker tag nodejs-app:manual "$(terraform output -raw nodejs_app_ecr_repository_url):manual"
docker push "$(terraform output -raw nodejs_app_ecr_repository_url):manual"
```

Then update the image field in your Kubernetes manifest to:

```text
<repository-url>:manual
```

## Phase 7: Deploy Argo CD And Applications

Apply Argo CD:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch configmap argocd-cmd-params-cm \
  -n argocd \
  --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout status deployment argocd-server -n argocd
kubectl apply -f k8s/argocd/argocd-ingress.yaml
kubectl apply -f k8s/argocd/root-app.yaml
```

Get the Argo CD ALB address:

```bash
kubectl get ingress -n argocd
```

Open the `ADDRESS` value with `http://` in your browser. This first setup uses the ALB DNS name over HTTP, so Argo CD server is configured with `server.insecure=true` and the ALB forwards to service port `80`.

For custom domain and TLS later, replace and uncomment the saved host, HTTPS listener, SSL redirect, and ACM certificate annotations in `k8s/argocd/argocd-ingress.yaml`.

Verify Argo CD apps:

```bash
kubectl get applications -n argocd
```

Verify observability platform pods:

```bash
kubectl get pods -n external-secrets
kubectl get pods -n elastic-system
kubectl get pods -n monitoring
kubectl get pods -n logging
```

Expected result:

- External Secrets pods are running.
- ECK operator pods are running.
- Prometheus/Grafana pods are running in `monitoring`.
- Elasticsearch, Kibana, Fluent Bit, and Jaeger pods are running in `logging`.

Verify workloads:

```bash
kubectl get pods -n qa
kubectl get pods -n prod
kubectl get externalsecret -A
kubectl get secret mysql-secret -n qa
kubectl get secret mysql-secret -n prod
kubectl get ingress -n qa
kubectl get ingress -n prod
```

Expected result:

- Argo CD applications are created.
- QA and production namespaces have app workloads.
- ExternalSecrets sync successfully.
- Kubernetes secrets named `mysql-secret` exist in `qa` and `prod`.
- Ingress resources are created.

Verify Grafana access by port-forward:

```bash
kubectl get secret grafana-admin-secret -n monitoring
kubectl port-forward -n monitoring svc/monitoring-stack-grafana 3000:80
```

Open:

```text
http://localhost:3000
```

Log in with:

```text
username: value from TF_VAR_grafana_admin_username
password: value from TF_VAR_grafana_admin_password
```

Verify Prometheus app metrics:

```bash
kubectl get servicemonitor -n qa
kubectl get servicemonitor -n prod
kubectl port-forward -n qa svc/nodejs-service 5000:5000
```

In another terminal:

```bash
curl http://localhost:5000/api/users
curl http://localhost:5000/metrics
```

Expected result:

- Metrics include `http_requests_total`.
- Metrics include `http_request_duration_seconds`.
- Metrics include default Node.js process metrics.

Verify EFK logs:

```bash
kubectl get pods -n logging
kubectl logs -n logging ds/fluent-bit
kubectl port-forward -n logging svc/logging-kb-kb-http 5601:5601
```

Open:

```text
https://localhost:5601
```

Generate app traffic before checking Kibana:

```bash
kubectl port-forward -n qa svc/nodejs-service 5000:5000
curl http://localhost:5000/api/users
```

Expected result:

- Elasticsearch and Kibana pods are running.
- Fluent Bit logs do not show repeated Elasticsearch output failures.
- App request logs appear as JSON messages after traffic reaches the app.

Verify Jaeger traces:

```bash
kubectl get pods -n logging | grep jaeger
kubectl port-forward -n logging svc/jaeger-query 16686:80
```

Open:

```text
http://localhost:16686
```

Generate app traffic before checking Jaeger:

```bash
kubectl port-forward -n qa svc/nodejs-service 5000:5000
curl http://localhost:5000/api/users
```

Expected result:

- Jaeger UI opens.
- After sending traffic to the app, services include `nodejs-app-qa` or `nodejs-app-prod`.
- Traces include HTTP, Express, and MySQL spans.

Troubleshooting:

- If Argo CD applications are missing, confirm `k8s/argocd/root-app.yaml` was applied to the correct cluster.
- If pods are pending, describe the pod and check scheduling, image pull, and storage events:

```bash
kubectl describe pod -n qa <pod-name>
kubectl describe pod -n prod <pod-name>
```

- If pods crash, check logs:

```bash
kubectl logs -n qa deploy/nodejs-app
kubectl logs -n prod deploy/nodejs-app
```

- If ExternalSecrets fail, describe them:

```bash
kubectl describe externalsecret mysql-external-secret -n qa
kubectl describe externalsecret mysql-external-secret -n prod
```

- If ingress does not get an address, check the AWS Load Balancer Controller pods and events.
- If the app cannot connect to RDS in Kubernetes, confirm the synced secret contains `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and `DATABASE_URL`.
- If Grafana login fails, confirm `monitoring/grafana_secret` exists in AWS Secrets Manager and `grafana-admin-secret` exists in Kubernetes.
- If `/metrics` is missing, rebuild and redeploy the app image after the observability code changes.
- If Prometheus does not scrape the app, confirm the `ServiceMonitor` exists and the `nodejs-service` port is named `http`.
- If Kibana does not show app logs, generate traffic against the app and confirm Fluent Bit is running on the node that hosts the app pod.
- If Jaeger shows no traces, confirm the app deployment has `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` and the Jaeger collector service is running.

## Useful Cleanup Commands

Stop local Docker Compose stack:

```bash
docker compose down
```

Delete local MySQL Compose data:

```bash
docker compose down -v
```

Delete Kubernetes workloads:

```bash
kubectl delete -f k8s/prod/
kubectl delete -f k8s/qa/
```

Destroy cloud infrastructure:

```bash
cd terraform/environments/prod
terraform destroy
```

Destroy the Terraform backend only after all environment state has been removed or migrated:

```bash
cd terraform/backend
terraform destroy
```
