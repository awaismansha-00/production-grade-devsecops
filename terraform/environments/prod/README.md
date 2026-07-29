# Production Terraform Environment

This directory is the production root module. It should stay thin: provider configuration, backend configuration, environment variables, module calls, outputs, and small cross-module wiring belong here.

Reusable infrastructure belongs in `terraform/modules/`.

## Modules

The production environment wires these modules:

```text
../../modules/vpc
../../modules/eks
../../modules/ecr
../../modules/eks-addons
../../modules/rds-mysql
../../modules/mysql-bootstrap
../../modules/ssm-tunnel-host
../../modules/github-actions-ecr-role
```

## Responsibilities

- VPC and private/public subnet networking.
- EKS cluster and managed node group.
- EKS add-ons: AWS Load Balancer Controller, External Secrets Operator, EBS CSI, and `ebs-sc`.
- ECR repository for the Node.js application image.
- Private shared RDS MySQL instance.
- QA/prod MySQL database and user bootstrap.
- AWS Secrets Manager values consumed by External Secrets.
- GitHub Actions OIDC role for ECR access.

## MySQL Bootstrap

RDS remains private. The MySQL Terraform provider should connect through local port `3307`.

For this portfolio project, use a private SSM-managed tunnel host:

```bash
aws ssm start-session \
  --target "$(terraform output -raw ssm_tunnel_instance_id)" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$(terraform output -raw rds_mysql_address)\"],\"portNumber\":[\"3306\"],\"localPortNumber\":[\"3307\"]}"
```

For a larger production setup, run Terraform from inside the VPC with CodeBuild, a self-hosted GitHub runner, or Terraform Cloud Agent.

## GitHub Actions Access

GitHub Actions should authenticate to AWS with OIDC and short-lived credentials.

Use the Terraform-managed GitHub Actions ECR role ARN as:

```text
AWS_ROLE_TO_ASSUME
```

Use these repository variables:

```text
AWS_REGION
ECR_REPOSITORY
```

Do not use long-lived AWS access keys for the CI/CD pipelines.

## Validation

```bash
terraform fmt -check -recursive
terraform -chdir=terraform/environments/prod init
terraform -chdir=terraform/environments/prod validate
terraform -chdir=terraform/environments/prod plan -var='enable_mysql_bootstrap=false'
```

After RDS and the SSM tunnel host exist, open the tunnel and run:

```bash
terraform -chdir=terraform/environments/prod plan -var='enable_mysql_bootstrap=true'
```
