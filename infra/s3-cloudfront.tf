# --------------------------------------------------------------------------
# S3 bucket for the Angular SPA
# --------------------------------------------------------------------------
resource "aws_s3_bucket" "spa" {
  bucket        = "angular-micro-spa-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "spa" {
  bucket                  = aws_s3_bucket.spa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spa" {
  bucket = aws_s3_bucket.spa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# --------------------------------------------------------------------------
# CloudFront OAC — restricts S3 reads to the CloudFront distribution only
# --------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "angular-micro-spa-oac"
  description                       = "OAC for the Angular SPA bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --------------------------------------------------------------------------
# CloudFront distribution — two origins: S3 (default) and the ALB (/api/*)
# --------------------------------------------------------------------------
# Managed cache + origin request policy IDs from AWS docs:
#   CachingOptimized:            658327ea-f89d-4fab-a63d-7e88639e58f6
#   CachingDisabled:             4135ea2d-6df8-44a3-9df3-4b5a84be39ad
#   AllViewerExceptHostHeader:   b689b0a8-53d0-40ab-baf2-68738e2966ac
#
# Gated on skip_cloudfront so the first apply can defer CloudFront until
# after the ALB exists (CloudFront errors out if the origin DNS isn't
# resolvable yet — same two-phase approach as the EKS version).
# --------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "spa" {
  count = var.skip_cloudfront ? 0 : 1

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Angular SPA + /api/* proxy to ECS ALB"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "spa-s3"
    domain_name              = aws_s3_bucket.spa.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  origin {
    origin_id   = "api-alb"
    domain_name = aws_lb.api.dns_name

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }
  }

  default_cache_behavior {
    target_origin_id       = "spa-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "api-alb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# --------------------------------------------------------------------------
# S3 bucket policy — grant the distribution principal s3:GetObject
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "spa_bucket" {
  count = var.skip_cloudfront ? 0 : 1

  statement {
    sid     = "AllowCloudFrontOACRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.spa.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.spa[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "spa" {
  count  = var.skip_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.spa.id
  policy = data.aws_iam_policy_document.spa_bucket[0].json
}
