data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "pod_identity_assume_role" {
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

# ------------------------------------------------------------

resource "aws_iam_role" "aws_lbc_role" {
  name               = "${var.cluster_name}-aws-lbc-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
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

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set = [{
    name  = "clusterName"
    value = var.cluster_name
    }
    , {
      name  = "serviceAccount.create"
      value = "true"
    }

    , {
      name  = "serviceAccount.name"
      value = var.aws_lbc_service_account_name
    }
    , {
      name  = "vpcId"
      value = var.vpc_id
    }
  ]

  depends_on = [aws_iam_role_policy_attachment.aws_lbc_policy_attachment]

}

resource "aws_eks_pod_identity_association" "aws_lbc_pod_identity_association" {

  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = var.aws_lbc_service_account_name
  role_arn        = aws_iam_role.aws_lbc_role.arn

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}
# ------------------------------------------------------------

resource "aws_iam_policy" "external_secrets_policy" {
  name = "${var.cluster_name}-external-secrets-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.external_secret_arns
      }
    ]
  })
}

resource "aws_iam_role" "external_secrets_role" {
  name               = "${var.cluster_name}-external-secrets-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "external_secrets_policy_attachment" {
  role       = aws_iam_role.external_secrets_role.name
  policy_arn = aws_iam_policy.external_secrets_policy.arn
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  set = [{
    name  = "installCRDs"
    value = "true"
    }
    , {
      name  = "serviceAccount.create"
      value = "true"
    }
    , {
      name  = "serviceAccount.name"
      value = var.external_secrets_service_account_name
    }
  ]

}

resource "aws_eks_pod_identity_association" "external_secrets_pod_identity_association" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets_role.arn

  depends_on = [
    helm_release.external_secrets,
    aws_iam_role_policy_attachment.external_secrets_policy_attachment
  ]
}

# ------------------------------------------------------------
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.cluster_name
  addon_name   = "aws-ebs-csi-driver"
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_eks_addon.ebs_csi,
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}

resource "aws_iam_role" "ebs_csi_role" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}





resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "ebs-sc"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }

  depends_on = [aws_eks_pod_identity_association.ebs_csi]
}
