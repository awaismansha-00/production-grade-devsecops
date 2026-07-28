# Integration Fix Guide

This guide lists only the integration fixes still needed after the latest project review.

Do not change dummy AWS account IDs, hostnames, or ACM certificate values here. Terraform formatting is still planned for the end.

## Current State

Already completed:

- Terraform modules now exist for `ecr`, `eks-addons`, `rds-mysql`, and `mysql-bootstrap`.
- `terraform/environments/prod` is moving toward a thin root module that wires reusable modules together.
- QA/prod MySQL StatefulSet and Service manifests have been deleted.
- QA/prod app deployments now read `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and `DATABASE_URL` from `mysql-secret`.
- Argo QA watches the `qa` branch, and Argo prod watches the `prod` branch.
- GitHub Actions has been partially migrated from Docker image registry credentials to AWS/ECR auth.

Still needed:

1. Add a private SSM-managed tunnel host instead of using a public SSH bastion.
2. Allow RDS ingress from both EKS and the SSM tunnel host.
3. Add a Terraform-managed GitHub OIDC role for ECR.
4. Fix the missing root `aws_caller_identity` data source.
5. Fix QA/prod ExternalSecret YAML shape and prod secret references.
6. Fix the server DB pool usage.
7. Fix cross-job ECR image passing in GitHub Actions.
8. Update validation and docs after implementation.

## Architecture Decision

For this portfolio project, use:

- One shared EKS cluster.
- One private shared Amazon RDS MySQL instance.
- Separate namespaces: `qa` and `prod`.
- Separate MySQL databases and users for QA/prod.
- Separate AWS Secrets Manager secrets: `qa/mysql_secret` and `prod/mysql_secret`.

This is cost-aware and production-shaped. RDS is better than MySQL inside EKS for the app database because AWS manages backups, restore workflows, patching, storage durability, and database lifecycle operations.

For a larger real production system, split environments further with separate AWS accounts, separate EKS clusters, and separate RDS/Aurora instances.

## 1. Add Missing AWS Caller Identity Data Source

Current issue:

`terraform/environments/prod/main.tf` uses:

```hcl
data.aws_caller_identity.current.account_id
```

but the root module does not currently define `data "aws_caller_identity" "current" {}`.

In:

```text
terraform/environments/prod/main.tf
```

add this near the AWS provider:

```hcl
data "aws_caller_identity" "current" {}
```

Recommended placement:

```hcl
provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
```

## 2. Use SSM Tunnel Host, Not A Public Bastion

Recommended professional approach for this project:

- Keep RDS private.
- Do not create a public SSH bastion.
- Create a private EC2 instance managed by AWS Systems Manager Session Manager.
- Do not open inbound SSH.
- Use IAM and SSM port forwarding when Terraform needs to reach MySQL.

This is cleaner than a traditional public bastion because it avoids public inbound ports and SSH key management.

Future market-standard upgrade:

- Run Terraform from inside the VPC through CodeBuild, a self-hosted GitHub runner, Terraform Cloud Agent, or another private runner.

## 3. Add `ssm-tunnel-host` Module

Create:

```text
terraform/modules/ssm-tunnel-host/main.tf
terraform/modules/ssm-tunnel-host/variables.tf
terraform/modules/ssm-tunnel-host/outputs.tf
```

`terraform/modules/ssm-tunnel-host/variables.tf`:

```hcl
variable "name_prefix" {
  description = "Prefix used for tunnel host resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the SSM tunnel host"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the SSM tunnel host"
  type        = string
  default     = "t3.micro"
}
```

`terraform/modules/ssm-tunnel-host/main.tf`:

```hcl
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name_prefix}-ssm-tunnel-sg"
  description = "Private SSM tunnel host security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-ssm-tunnel-sg"
  }
}

resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-ssm-tunnel-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-ssm-tunnel-profile"
  role = aws_iam_role.this.name
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.name_prefix}-ssm-tunnel"
  }
}
```

`terraform/modules/ssm-tunnel-host/outputs.tf`:

```hcl
output "instance_id" {
  description = "SSM tunnel host instance ID"
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "SSM tunnel host security group ID"
  value       = aws_security_group.this.id
}
```

## 4. Allow RDS From EKS And SSM Tunnel Host

Current issue:

`terraform/modules/rds-mysql` currently accepts only one allowed security group:

```hcl
variable "allowed_security_group_id" {
  description = "Security group allowed to connect to RDS on port 3306"
  type        = string
}
```

Replace it in:

```text
terraform/modules/rds-mysql/variables.tf
```

with:

```hcl
variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect to RDS on port 3306"
  type        = list(string)
}
```

In:

```text
terraform/modules/rds-mysql/main.tf
```

replace:

```hcl
resource "aws_security_group_rule" "mysql_from_eks" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = var.allowed_security_group_id
}
```

with:

```hcl
resource "aws_security_group_rule" "mysql_ingress" {
  for_each = toset(var.allowed_security_group_ids)

  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.this.id
  source_security_group_id = each.value
}
```

In:

```text
terraform/environments/prod/main.tf
```

add the SSM tunnel module before `module "rds_mysql"`:

```hcl
module "ssm_tunnel_host" {
  source = "../../modules/ssm-tunnel-host"

  name_prefix = var.cluster_name
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.private_subnet_ids[0]

  depends_on = [module.vpc]
}
```

Then replace:

```hcl
allowed_security_group_id = module.eks.cluster_security_group_id
```

with:

```hcl
allowed_security_group_ids = [
  module.eks.cluster_security_group_id,
  module.ssm_tunnel_host.security_group_id
]
```

In:

```text
terraform/environments/prod/outputs.tf
```

add:

```hcl
output "rds_mysql_address" {
  description = "RDS MySQL address"
  value       = module.rds_mysql.address
}

output "ssm_tunnel_instance_id" {
  description = "SSM tunnel host instance ID"
  value       = module.ssm_tunnel_host.instance_id
}
```

## 5. Gate MySQL Bootstrap For Two-Phase Apply

Current issue:

Terraform cannot use the MySQL provider against private RDS until RDS and the SSM tunnel host exist.

Add this variable in:

```text
terraform/environments/prod/variables.tf
```

```hcl
variable "enable_mysql_bootstrap" {
  description = "Enable MySQL database/user bootstrap after RDS and SSM tunnel are reachable"
  type        = bool
  default     = false
}
```

In:

```text
terraform/environments/prod/main.tf
```

replace the existing `module "mysql_bootstrap"` block header:

```hcl
module "mysql_bootstrap" {
  source = "../../modules/mysql-bootstrap"
```

with:

```hcl
module "mysql_bootstrap" {
  count  = var.enable_mysql_bootstrap ? 1 : 0
  source = "../../modules/mysql-bootstrap"
```

Apply flow:

```bash
terraform -chdir=terraform/environments/prod apply -var='enable_mysql_bootstrap=false'
```

Start the tunnel:

```bash
aws ssm start-session \
  --target "$(terraform -chdir=terraform/environments/prod output -raw ssm_tunnel_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(terraform -chdir=terraform/environments/prod output -raw rds_mysql_address)\"],\"portNumber\":[\"3306\"],\"localPortNumber\":[\"3307\"]}"
```

Keep the tunnel terminal open, then run:

```bash
terraform -chdir=terraform/environments/prod apply -var='enable_mysql_bootstrap=true'
```

Keep this MySQL provider config in root:

```hcl
provider "mysql" {
  endpoint = "127.0.0.1:3307"
  username = var.rds_master_username
  password = var.rds_master_password
}
```

## 6. Add GitHub OIDC Role For ECR Through Terraform

Yes, create the GitHub Actions OIDC role through Terraform.

Create:

```text
terraform/modules/github-actions-ecr-role/main.tf
terraform/modules/github-actions-ecr-role/variables.tf
terraform/modules/github-actions-ecr-role/outputs.tf
```

`terraform/modules/github-actions-ecr-role/variables.tf`:

```hcl
variable "name_prefix" {
  description = "Prefix used for IAM resources"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/name format"
  type        = string
}

variable "branches" {
  description = "Branches allowed to assume the role"
  type        = list(string)
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN"
  type        = string
}
```

`terraform/modules/github-actions-ecr-role/main.tf`:

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for branch in var.branches :
        "repo:${var.github_repository}:ref:refs/heads/${branch}"
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name_prefix}-github-actions-ecr-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "ecr" {
  statement {
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_policy" "ecr" {
  name   = "${var.name_prefix}-github-actions-ecr-policy"
  policy = data.aws_iam_policy_document.ecr.json
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.ecr.arn
}
```

`terraform/modules/github-actions-ecr-role/outputs.tf`:

```hcl
output "role_arn" {
  description = "IAM role ARN for GitHub Actions ECR access"
  value       = aws_iam_role.this.arn
}
```

Important: the GitHub OIDC provider is one per AWS account. If it already exists, import it instead of trying to create a duplicate:

```bash
terraform -chdir=terraform/environments/prod import \
  'module.github_actions_ecr_role.aws_iam_openid_connect_provider.github' \
  arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com
```

In:

```text
terraform/environments/prod/main.tf
```

add:

```hcl
module "github_actions_ecr_role" {
  source = "../../modules/github-actions-ecr-role"

  name_prefix        = var.cluster_name
  github_repository  = "awaismansha-00/production-grade-devsecops"
  branches           = ["qa", "prod"]
  ecr_repository_arn = module.ecr.repository_arn
}
```

In:

```text
terraform/environments/prod/outputs.tf
```

add:

```hcl
output "github_actions_ecr_role_arn" {
  description = "IAM role ARN used by GitHub Actions for ECR"
  value       = module.github_actions_ecr_role.role_arn
}
```

Set the GitHub repository secret:

```text
AWS_ROLE_TO_ASSUME=<github_actions_ecr_role_arn output>
```

Keep these repository variables:

```text
AWS_REGION=eu-west-2
ECR_REPOSITORY=nodejs-app
```

## 7. Fix QA ExternalSecret YAML

Current issue:

`data:` is nested under `target:`. It must be a sibling of `target:` under `spec:`.

In:

```text
k8s/qa/external-secret.yaml
```

replace the whole file with:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mysql-external-secret
  namespace: qa
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: mysql-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: qa/mysql_secret
        property: DB_HOST
    - secretKey: DB_NAME
      remoteRef:
        key: qa/mysql_secret
        property: DB_NAME
    - secretKey: DB_USER
      remoteRef:
        key: qa/mysql_secret
        property: DB_USER
    - secretKey: DB_PASSWORD
      remoteRef:
        key: qa/mysql_secret
        property: DB_PASSWORD
    - secretKey: DATABASE_URL
      remoteRef:
        key: qa/mysql_secret
        property: DATABASE_URL
```

## 8. Fix Prod ExternalSecret YAML

Current issues:

- `data:` is nested under `target:`.
- Prod still reads from `qa/mysql_secret`.

In:

```text
k8s/prod/external-secret.yaml
```

replace the whole file with:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mysql-external-secret
  namespace: prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: mysql-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_HOST
      remoteRef:
        key: prod/mysql_secret
        property: DB_HOST
    - secretKey: DB_NAME
      remoteRef:
        key: prod/mysql_secret
        property: DB_NAME
    - secretKey: DB_USER
      remoteRef:
        key: prod/mysql_secret
        property: DB_USER
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/mysql_secret
        property: DB_PASSWORD
    - secretKey: DATABASE_URL
      remoteRef:
        key: prod/mysql_secret
        property: DATABASE_URL
```

## 9. Fix Server DB Pool Usage

Current issue:

`server/config/db.js` exports a MySQL pool, but `server/server.js` still calls:

```js
db.connect((err) => {
```

Pools do not use `db.connect(...)`.

In:

```text
server/server.js
```

replace the whole startup connection block:

```js
db.connect((err) => {
  if (err) {
    console.error('Database connection failed:', err.stack);
    process.exit(1);
  }
  console.log('Database connected.');

  // Initialize database with `users` table if it doesn't exist
  const createUsersTable = `
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL UNIQUE,
      role ENUM('Admin', 'User') NOT NULL
    )
  `;

  db.query(createUsersTable, (err, results) => {
    if (err) {
      console.error('Failed to create users table:', err.stack);
      process.exit(1);
    }
    console.log('Users table initialized or already exists.');
  });
});
```

with:

```js
const createUsersTable = `
  CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    role ENUM('Admin', 'User') NOT NULL
  )
`;

db.query(createUsersTable, (err) => {
  if (err) {
    console.error('Failed to initialize users table:', err.stack);
    process.exit(1);
  }
  console.log('Database connected and users table initialized or already exists.');
});
```

Later, replace startup table creation with a migration tool.

## 10. Fix QA Workflow ECR Image Passing

Current issues:

- QA workflow trigger paths do not include `Dockerfile` or `.dockerignore`.
- `update-image-in-qa-k8s-manifest` uses `steps.login-ecr.outputs.registry`, but that step runs in a different job.

In:

```text
.github/workflows/qa-cicd.yaml
```

replace:

```yaml
paths:
    - client/**
    - server/**
    - .github/workflows/qa-cicd.yaml
```

with:

```yaml
paths:
  - client/**
  - server/**
  - Dockerfile
  - .dockerignore
  - .github/workflows/qa-cicd.yaml
```

In the `docker-build-push` job, add outputs:

```yaml
outputs:
  image_sha: ${{ steps.image.outputs.sha }}
  image_latest: ${{ steps.image.outputs.latest }}
```

Place them at the same indentation level as `runs-on`.

After the ECR login step, add:

```yaml
- name: Set ECR image names
  id: image
  run: |
    echo "sha=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:${{ github.sha }}" >> "$GITHUB_OUTPUT"
    echo "latest=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:latest" >> "$GITHUB_OUTPUT"
```

Then replace image references inside the `docker-build-push` job:

```text
${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:${{ github.sha }}
${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:latest
```

with:

```text
${{ steps.image.outputs.sha }}
${{ steps.image.outputs.latest }}
```

In `update-image-in-qa-k8s-manifest`, replace:

```bash
IMAGE="${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:${{ github.sha }}"
```

with:

```bash
IMAGE="${{ needs.docker-build-push.outputs.image_sha }}"
```

## 11. Fix Prod Workflow ECR Image Passing

Current issue:

`update-prod-k8s-manifest` uses `steps.login-ecr.outputs.registry`, but the login step runs in `promote-image-to-prod`.

In:

```text
.github/workflows/prod-cd.yaml
```

in `promote-image-to-prod`, add outputs:

```yaml
outputs:
  prod_image: ${{ steps.image.outputs.prod }}
```

Place them at the same indentation level as `runs-on`.

Replace:

```yaml
- name: Set ECR image names
  run: |
    echo "QA_IMAGE=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:latest" >> "$GITHUB_ENV"
    echo "PROD_LATEST_IMAGE=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:prod-${{ github.sha }}" >> "$GITHUB_ENV"
```

with:

```yaml
- name: Set ECR image names
  id: image
  run: |
    echo "qa=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:latest" >> "$GITHUB_OUTPUT"
    echo "prod=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:prod-${{ github.sha }}" >> "$GITHUB_OUTPUT"
    echo "QA_IMAGE=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:latest" >> "$GITHUB_ENV"
    echo "PROD_LATEST_IMAGE=${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:prod-${{ github.sha }}" >> "$GITHUB_ENV"
```

In `update-prod-k8s-manifest`, replace:

```bash
IMAGE="${{ steps.login-ecr.outputs.registry }}/${{ vars.ECR_REPOSITORY }}:prod-${{ github.sha }}"
```

with:

```bash
IMAGE="${{ needs.promote-image-to-prod.outputs.prod_image }}"
```

## 12. Validation

Run formatting at the end:

```bash
terraform fmt -recursive
terraform fmt -check -recursive
```

Initialize modules after adding `ssm-tunnel-host` and `github-actions-ecr-role`:

```bash
terraform -chdir=terraform/environments/prod init
```

Validate Terraform:

```bash
terraform -chdir=terraform/environments/prod validate
terraform -chdir=terraform/environments/prod plan -var='enable_mysql_bootstrap=false'
```

After RDS and SSM tunnel host exist, start the tunnel and validate bootstrap:

```bash
terraform -chdir=terraform/environments/prod plan -var='enable_mysql_bootstrap=true'
```

Validate YAML:

```bash
python3 -c "import yaml, pathlib; files=list(pathlib.Path('k8s').rglob('*.yaml')); [list(yaml.safe_load_all(f.read_text())) for f in files]; print('parsed', len(files), 'k8s yaml files')"
python3 -c "import yaml, pathlib; files=list(pathlib.Path('.github/workflows').glob('*.y*ml')); [list(yaml.safe_load_all(f.read_text())) for f in files]; print('parsed', len(files), 'workflow yaml files')"
```

Check stale references:

```bash
rg -n "mysql-statefulset|kind: StatefulSet|serviceName: mysql|value: mysql|MYSQL_ROOT_PASSWORD|MYSQL_DATABASE|MYSQL_USER|MYSQL_PASSWORD" k8s/ server/
rg -n "Docker Hub|DOCKER_USERNAME|DOCKERHUB_TOKEN|awaismansha/nodejs-app|docker/login-action" .github/workflows README.md terraform/environments/prod/README.md
```

Expected:

- Terraform modules install successfully.
- RDS allows port `3306` from EKS and the SSM tunnel host.
- MySQL bootstrap can run only after the SSM tunnel is open.
- GitHub Actions uses AWS OIDC and ECR.
- QA/prod ExternalSecrets create correct `mysql-secret` values.
- App pods connect to RDS and the API can read/write users.

## References

- AWS Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
- SSM port forwarding to remote hosts: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html
- GitHub OIDC for AWS: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws
- Terraform `aws_iam_openid_connect_provider`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider
