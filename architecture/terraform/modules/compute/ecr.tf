# dagster   Dagster webserver/daemon + the code location (assets, sensors)
# pipeline  dlt + Soda + dbt project, launched per run by Dagster
# metabase  pinned mirror of metabase/metabase, so nothing pulls from Docker Hub

resource "aws_ecr_repository" "this" {
  for_each             = toset(["dagster", "pipeline", "metabase"])
  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "KMS"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}
