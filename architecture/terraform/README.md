# Pokeplan infrastructure (Terraform)

The AWS side of the architecture page (https://claude.ai/artifact/VKQruF35cyaowFznme2MEo).
Nothing here has been applied. It validates, and `terraform test` plans both layouts
against a mocked AWS provider.

```
live/                 the one stack; pick a layout with a tfvars file
  prod.tfvars         2 AZs, Network Firewall, NAT per AZ, 12 interface endpoints, Multi-AZ RDS
  learning.tfvars     DNS Firewall instead, one NAT, no interface endpoints, single-AZ RDS
  tests/              mocked plans of both layouts
modules/
  network/            VPC, 5 subnet tiers, NAT, Network Firewall or DNS Firewall, endpoints, flow logs
  storage/            KMS keys, raw / lake / athena buckets, Glue databases, Athena workgroup
  events/             EventBridge bus + archive, SQS queues + DLQs, SNS topics, nightly commit check
  iam/                one role per job, ECS execution role, GitHub OIDC deploy role
  governance/         Lake Formation admins, registered buckets, per-role grants
  compute/            ECS cluster, Dagster, Metabase, pipeline task definitions, RDS, ALB + OIDC + WAF, ECR
lambdas/check_commit/ publishes ingest.requested with the latest PokeAPI/api-data commit
```

## Run order

```
cd live
terraform init -backend-config=backend-prod.hcl
terraform plan -var-file=prod.tfvars          # TF_VAR_oidc comes from CI secrets
terraform apply -var-file=prod.tfvars
```

Then CI builds and pushes the `dagster` and `pipeline` images and mirrors Metabase into ECR,
and a one-off migration creates the `dagster` and `metabase` databases and users on RDS.

## Not in this repo, on purpose

- Organization-wide controls (Control Tower, the organization CloudTrail into the log-archive
  account, GuardDuty, Security Hub, AWS Config) belong to the AWS Organization's own
  baseline, applied once for every account, not to one project.
- Iceberg tables. dlt and dbt create them; Terraform only creates the Glue databases and grants.
- DNS records and the ACM certificate, which depend on where your domain is hosted.

## Things to know

- With Network Firewall on, outbound HTTPS is allowed only to pokeapi.co and github.com
  (plus subdomains). Add a domain in `modules/network/variables.tf` before anything new can reach it.
- The learning layout's DNS Firewall only filters name lookups. It is a cheap stand-in, not a
  real egress control.
- Bucket policies reject writes that do not come through the VPC's S3 endpoint or through Athena.
  Running dlt from a laptop against these buckets therefore fails; run it as an ECS task or use the
  learning account.
