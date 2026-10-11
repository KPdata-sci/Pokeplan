# Three buckets, each with its own KMS key:
#   raw      dlt lands PokeAPI responses here (Iceberg table pokeplan_raw.api_response)
#   lake     dbt writes staging and mart Iceberg tables here
#   athena   query results, expired after 30 days

data "aws_caller_identity" "current" {}

locals {
  buckets = {
    raw    = "${var.name}-raw-${data.aws_caller_identity.current.account_id}"
    lake   = "${var.name}-lake-${data.aws_caller_identity.current.account_id}"
    athena = "${var.name}-athena-${data.aws_caller_identity.current.account_id}"
  }
}

resource "aws_kms_key" "this" {
  for_each                = local.buckets
  description             = "${var.name} ${each.key} data"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "this" {
  for_each      = local.buckets
  name          = "alias/${var.name}-${each.key}"
  target_key_id = aws_kms_key.this[each.key].key_id
}

resource "aws_s3_bucket" "this" {
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this[each.key].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena" {
  bucket = aws_s3_bucket.this["athena"].id
  rule {
    id     = "expire-results"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# Old Iceberg data files become noncurrent versions; keep them 90 days for rollback.
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  for_each = toset(["raw", "lake"])
  bucket   = aws_s3_bucket.this[each.key].id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  for_each = aws_s3_bucket.this

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Writes must come from inside the VPC, unless Athena is writing on the
  # caller's behalf (CTAS / Iceberg INSERT from dbt and dlt).
  statement {
    sid       = "DenyWritesOutsideVpc"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${each.value.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEqualsIfExists"
      variable = "aws:SourceVpce"
      values   = [var.s3_endpoint_id]
    }
    condition {
      test     = "ForAllValues:StringNotEquals"
      variable = "aws:CalledVia"
      values   = ["athena.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each   = aws_s3_bucket.this
  bucket     = each.value.id
  policy     = data.aws_iam_policy_document.bucket[each.key].json
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------- Glue catalog + Athena ----------

resource "aws_glue_catalog_database" "this" {
  for_each     = { raw = "raw", staging = "lake", mart = "lake" }
  name         = "${replace(var.name, "-", "_")}_${each.key}"
  location_uri = "s3://${aws_s3_bucket.this[each.value].bucket}/${each.key}/"
}

resource "aws_athena_workgroup" "pipeline" {
  name          = var.name
  force_destroy = var.force_destroy

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    result_configuration {
      output_location = "s3://${aws_s3_bucket.this["athena"].bucket}/results/"
      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = aws_kms_key.this["athena"].arn
      }
    }
  }
}
