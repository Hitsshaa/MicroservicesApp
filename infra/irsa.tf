# IAM Roles for Service Accounts (IRSA) — one role per app pod, scoped to
# secretsmanager:GetSecretValue on just its own secret ARN.

locals {
  irsa_apps = {
    user_service = {
      sa_name    = "user-service-sa"
      secret_arn = aws_secretsmanager_secret.user_db.arn
    }
    product_service = {
      sa_name    = "product-service-sa"
      secret_arn = aws_secretsmanager_secret.product_db.arn
    }
  }
}

data "aws_iam_policy_document" "user_service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.namespace}:user-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "product_service_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.namespace}:product-service-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "user_service_irsa" {
  name               = "angular-micro-user-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.user_service_trust.json
}

resource "aws_iam_role" "product_service_irsa" {
  name               = "angular-micro-product-service-irsa"
  assume_role_policy = data.aws_iam_policy_document.product_service_trust.json
}

data "aws_iam_policy_document" "user_service_secret_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.user_db.arn]
  }
}

data "aws_iam_policy_document" "product_service_secret_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.product_db.arn]
  }
}

resource "aws_iam_role_policy" "user_service_secret_read" {
  name   = "secrets-read"
  role   = aws_iam_role.user_service_irsa.id
  policy = data.aws_iam_policy_document.user_service_secret_read.json
}

resource "aws_iam_role_policy" "product_service_secret_read" {
  name   = "secrets-read"
  role   = aws_iam_role.product_service_irsa.id
  policy = data.aws_iam_policy_document.product_service_secret_read.json
}
