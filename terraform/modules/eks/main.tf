resource "aws_iam_role" "cluster_role" {
  name = "${var.cluster_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy_attachment" "cluster_policy_attachment" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "main_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy_attachment
  ]
}

resource "aws_iam_role" "node_role" {
  name = "${var.cluster_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy_attachment" {
  role = aws_iam_role.node_role.name
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ])

  policy_arn = each.value
}

resource "aws_eks_node_group" "main_node_group" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.main_cluster.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = each.value.scaling_config.desired_size
    max_size     = each.value.scaling_config.max_size
    min_size     = each.value.scaling_config.min_size
  }

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type

  depends_on = [aws_iam_role_policy_attachment.node_policy_attachment]

}


resource "aws_eks_addon" "pod_identity" {
  cluster_name  = aws_eks_cluster.main_cluster.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.2.0-eksbuild.1"

  depends_on = [
    aws_eks_node_group.main_node_group
  ]
}



data "aws_iam_policy_document" "aws_lbc_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }

}

resource "aws_iam_role" "aws_lbc_role" {
  name               = "${var.cluster_name}-aws-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.aws_lbc_policy.json
}

resource "aws_iam_policy" "aws_lbc_policy" {
  name        = "${var.cluster_name}-aws-lbc-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/awslbcpolicy.json")

}

resource "aws_iam_role_policy_attachment" "aws_lbc_policy_attachment" {
  role       = aws_iam_role.aws_lbc_role.name
  policy_arn = aws_iam_policy.aws_lbc_policy.arn
}

resource "aws_eks_pod_identity_association" "aws_lbc_pod_identity_association" {

  cluster_name    = aws_eks_cluster.main_cluster.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lbc_role.arn

  depends_on = [
    helm_release.aws_load_balancer_controller,
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.aws_lbc_policy_attachment
  ]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set = [{
    name  = "clusterName"
    value = aws_eks_cluster.main_cluster.name
    }

    , {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    }
    , {
      name  = "vpcId"
      value = var.vpc_id
    }
  ]

}
#----------------------------------------------------------------
data "aws_caller_identity" "current" {}

locals {
  environments = {
    qa = {
      namespace            = "qa"
      service_account_name = "eso-qa-sa"
      secret_prefix        = "qa"
    }

    prod = {
      namespace            = "prod"
      service_account_name = "eso-prod-sa"
      secret_prefix        = "prod"
    }
  }
}

resource "aws_iam_policy" "external_secrets_policy" {
  for_each = local.environments
  name     = "${var.cluster_name}-${each.key}-external-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${each.value.secret_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role" "external_secrets_role" {
  for_each = local.environments
  name     = "${var.cluster_name}-${each.key}-external-secrets-role"

  assume_role_policy = data.aws_iam_policy_document.aws_lbc_policy.json
}

resource "aws_iam_role_policy_attachment" "external_secrets_policy_attachment" {
  for_each   = local.environments
  role       = aws_iam_role.external_secrets_role[each.key].name
  policy_arn = aws_iam_policy.external_secrets_policy[each.key].arn
}

resource "aws_eks_pod_identity_association" "external_secrets_pod_identity_association" {
  for_each        = local.environments
  cluster_name    = aws_eks_cluster.main_cluster.name
  namespace       = each.value.namespace
  service_account = each.value.service_account_name
  role_arn        = aws_iam_role.external_secrets_role[each.key].arn

  depends_on = [
    aws_eks_addon.pod_identity,
    aws_iam_role_policy_attachment.external_secrets_policy_attachment
  ]
}
