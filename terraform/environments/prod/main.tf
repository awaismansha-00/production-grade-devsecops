terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    mysql = {
      source  = "petoju/mysql"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "production-grade-devsecops-state-bucket"
    key          = "terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}

data "aws_eks_cluster" "main" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "main" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

provider "mysql" {
  endpoint = "127.0.0.1:3307"
  username = var.rds_master_username
  password = var.rds_master_password
}

module "vpc" {
  source               = "../../modules/vpc"
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "eks" {
  source          = "../../modules/eks"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  node_groups     = var.node_groups
  region          = var.region
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name      = "nodejs-app"
  image_tag_mutability = "MUTABLE"
  scan_on_push         = true
}

module "eks_addons" {
  source = "../../modules/eks-addons"

  cluster_name = module.eks.cluster_name
  region       = var.region
  vpc_id       = module.vpc.vpc_id

  external_secret_arns = [
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:qa/*",
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:prod/*",
    "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:monitoring/*"
  ]

  depends_on = [module.eks]
}


module "ssm_tunnel_host" {
  source = "../../modules/ssm-tunnel-host"

  name_prefix = var.cluster_name
  vpc_id      = module.vpc.vpc_id
  subnet_id   = module.vpc.private_subnet_ids[0]

  depends_on = [module.vpc]
}

module "rds_mysql" {
  source = "../../modules/rds-mysql"

  name_prefix        = var.cluster_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  allowed_security_group_ids = [
    module.eks.cluster_security_group_id,
    module.ssm_tunnel_host.security_group_id
  ]
  master_username = var.rds_master_username
  master_password = var.rds_master_password

  depends_on = [module.eks]
}

module "mysql_bootstrap" {
  count  = var.enable_mysql_bootstrap ? 1 : 0
  source = "../../modules/mysql-bootstrap"

  qa_db_name       = var.qa_db_name
  qa_db_username   = var.qa_db_username
  qa_db_password   = var.qa_db_password
  prod_db_name     = var.prod_db_name
  prod_db_username = var.prod_db_username
  prod_db_password = var.prod_db_password

  depends_on = [module.rds_mysql]
}
module "github_actions_ecr_role" {
  source = "../../modules/github-actions-ecr-role"

  name_prefix        = var.cluster_name
  github_repository  = "awaismansha-00/production-grade-devsecops"
  branches           = ["qa", "prod"]
  ecr_repository_arn = module.ecr.repository_arn
}
