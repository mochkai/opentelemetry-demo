# Customer-owned archive buckets for Coralogix.
# Coralogix requires separate buckets for logs and metrics, in the team's region.

variable "coralogix_archive_role_arn" {
  description = "Coralogix-owned IAM role that writes to the archive buckets. EU2 value from Coralogix docs."
  type        = string
  default     = "arn:aws:iam::625240141681:role/coralogix-archive-eu2"
}

variable "archive_retention_days" {
  description = "Days before archived objects are expired from the customer bucket."
  type        = number
  default     = 365
}

output "archive_logs_bucket" {
  value = aws_s3_bucket.archive["logs"].id
}

output "archive_metrics_bucket" {
  value = aws_s3_bucket.archive["metrics"].id
}

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  archive_buckets = {
    logs    = "${var.project}-archive-logs-${random_id.suffix.hex}"
    metrics = "${var.project}-archive-metrics-${random_id.suffix.hex}"
  }
}

resource "aws_s3_bucket" "archive" {
  for_each = local.archive_buckets
  bucket   = each.value

  # Lab convenience so `terraform destroy` works with data in the bucket.
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced" # ACLs disabled; customer account owns every object
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 keeps the lab simple. SSE-KMS works too but the key policy must also
# grant the Coralogix role kms:Encrypt/Decrypt/ReEncrypt*/GenerateDataKey*/DescribeKey.
resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id

  rule {
    id     = "retention"
    status = "Enabled"
    filter {}

    expiration {
      days = var.archive_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "archive" {
  for_each = aws_s3_bucket.archive

  # Least-privilege grant to the Coralogix archive role (actions per Coralogix docs).
  statement {
    sid    = "CoralogixArchiveAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.coralogix_archive_role_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:DeleteObjectTagging",
      "s3:DeleteObjectVersionTagging",
    ]

    resources = [each.value.arn, "${each.value.arn}/*"]
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [each.value.arn, "${each.value.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  for_each = aws_s3_bucket.archive
  bucket   = each.value.id
  policy   = data.aws_iam_policy_document.archive[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.archive]
}
