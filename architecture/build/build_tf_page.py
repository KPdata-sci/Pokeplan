"""Builds the Pokeplan Terraform walkthrough page.

Each module is one tab: a plain-English summary, then short excerpts from the
real files, each with an explanation beside it. Excerpts are trimmed copies of
the files under terraform/ (trimmed lines are marked with a comment).
"""
import html, re, sys, pathlib

out = pathlib.Path(sys.argv[1])

# (tab id, tab label, file folder, intro sentence, [what it builds], [(file, code, explanation)])
TABS = [
("network", "Network", "modules/network",
 "The private network everything else runs inside, and the only ways in and out of it.",
 ["A VPC (10.40.0.0/16) spread over two availability zones.",
  "Five kinds of subnet per zone: public (load balancer), egress (NAT), app (containers), data (database, no way out), firewall.",
  "In prod, all outbound traffic passes Network Firewall, which only lets pokeapi.co and github.com through. The learning layout uses a cheaper DNS filter instead.",
  "Private connections to AWS services (S3, Athena, SQS and others), so that traffic never touches the internet.",
  "Flow logs of every connection."],
 [("main.tf",
'''resource "aws_subnet" "app" {
  for_each          = local.az_index
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr, 8, 10 + each.value)
}''',
 "One private subnet per availability zone for the containers. <code>for_each</code> repeats the block for each zone, and <code>cidrsubnet</code> cuts 10.40.10.0/24 and 10.40.11.0/24 out of the VPC range. The other four subnet kinds are the same block with different numbers."),
  ("main.tf",
'''resource "aws_route" "app_default" {
  for_each               = local.az_index
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = var.enable_network_firewall ? local.firewall_endpoints[each.key] : null
  nat_gateway_id         = var.enable_network_firewall ? null : aws_nat_gateway.this[local.nat_for[each.key]].id
}''',
 "Where the containers send internet traffic. In prod it goes to the firewall first, then NAT. In the learning layout it goes straight to NAT. The <code>condition ? a : b</code> form picks one based on the switch, and <code>null</code> means \"leave this unset\"."),
  ("firewall.tf",
'''rules_source_list {
  generated_rules_type = "ALLOWLIST"
  target_types         = ["TLS_SNI", "HTTP_HOST"]
  targets              = var.egress_domains
}

# from the firewall policy:
stateful_default_actions = ["aws:drop_established", "aws:alert_established"]''',
 "The allowlist. A connection is let out only if the website name it asks for is on <code>egress_domains</code> (pokeapi.co, github.com and their subdomains). Everything else is dropped and written to the alert log."),
 ]),
("storage", "Storage", "modules/storage",
 "Where the data lives: S3 buckets for the lakehouse, and the catalogue Athena uses to find tables.",
 ["Three buckets: <b>raw</b> (what dlt lands), <b>lake</b> (dbt's staging and mart tables), <b>athena</b> (query results, deleted after 30 days).",
  "A separate KMS encryption key for each bucket, rotated yearly.",
  "Public access blocked, versioning on, old versions kept 90 days so a bad load can be rolled back.",
  "Three Glue databases matching the star schema layers: raw, staging, mart.",
  "An Athena workgroup with a 10 GiB per-query limit as a cost guard."],
 [("main.tf",
'''resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.this[each.key].arn
    }
    bucket_key_enabled = true
  }
}''',
 "Every object in every bucket is encrypted with that bucket's own key. Looping over <code>aws_s3_bucket.this</code> means a new bucket added later gets this automatically."),
  ("main.tf",
'''statement {
  sid       = "DenyWritesOutsideVpc"
  effect    = "Deny"
  actions   = ["s3:PutObject", "s3:DeleteObject"]
  # ... resources and principals trimmed
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
}''',
 "Part of the bucket policy. It refuses any write that did not arrive through the VPC's private S3 connection, unless Athena is writing on dbt's behalf. Even a leaked AWS key used from a laptop cannot change the data."),
  ("main.tf",
'''resource "aws_glue_catalog_database" "this" {
  for_each     = { raw = "raw", staging = "lake", mart = "lake" }
  name         = "${replace(var.name, "-", "_")}_${each.key}"
  location_uri = "s3://${aws_s3_bucket.this[each.value].bucket}/${each.key}/"
}''',
 "The three schema layers as Glue databases: <code>pokeplan_prod_raw</code> in the raw bucket, and staging and mart in the lake bucket. Terraform makes only the databases; dlt and dbt create the tables inside them."),
 ]),
("events", "Events", "modules/events",
 "What makes the pipeline event-driven: a bus, rules that route each event, and the nightly trigger.",
 ["An EventBridge bus called <code>pokeplan-prod</code>, with every event archived for 30 days so a day can be replayed.",
  "<code>ingest.requested</code> and <code>raw.landed</code> are routed to two SQS queues that Dagster watches.",
  "<code>quality.failed</code>, <code>run.failed</code> and anything stuck in a dead-letter queue go to an alerts topic (email or Slack).",
  "A nightly 02:00 London schedule runs a small Lambda that reads the latest PokeAPI/api-data commit and publishes <code>ingest.requested</code>."],
 [("main.tf",
'''locals {
  queues = {
    ingest    = "ingest.requested"
    transform = "raw.landed"
  }
}

resource "aws_cloudwatch_event_rule" "queue" {
  for_each       = local.queues
  name           = "${var.name}-${each.key}"
  event_bus_name = aws_cloudwatch_event_bus.this.name
  event_pattern = jsonencode({
    source        = [local.source]
    "detail-type" = [each.value]
  })
}''',
 "The routing table. Each line in <code>queues</code> becomes a rule: \"when an event of this type arrives on the bus, send it to this queue\". Adding a new event type means adding one line here."),
  ("main.tf",
'''resource "aws_sqs_queue" "this" {
  for_each                   = local.queues
  name                       = "${var.name}-${each.key}"
  visibility_timeout_seconds = 300
  # ... retention and encryption trimmed
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = 3
  })
}''',
 "The two queues Dagster reads. If a message fails three times it moves to a dead-letter queue instead of retrying forever, and an alarm fires when that happens."),
  ("trigger.tf",
'''resource "aws_scheduler_schedule" "nightly" {
  name                         = "${var.name}-nightly"
  schedule_expression          = var.schedule          # cron(0 2 * * ? *)
  schedule_expression_timezone = var.schedule_timezone # Europe/London
  # ... flexible_time_window trimmed
  target {
    arn      = aws_lambda_function.check_commit.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}''',
 "Every night at 02:00 UK time, run the commit-check Lambda. It publishes the commit ID, and Dagster skips commits it has already loaded, so a quiet night costs nothing."),
 ]),
("iam", "Permissions", "modules/iam",
 "Who may do what. Each job gets its own role with only the access it needs.",
 ["<b>ingest</b> (dlt): write the raw bucket and raw tables, nothing else.",
  "<b>transform</b> (Soda and dbt): read raw, write staging and mart.",
  "<b>dagster</b>: read the two queues and start the ingest and transform tasks.",
  "<b>metabase</b>: read the mart tables through Athena.",
  "A deploy role that GitHub Actions can use from the main branch only, with no AWS keys stored anywhere."],
 [("main.tf",
'''# ingest role
statement {
  sid       = "RawBucketReadWrite"
  actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
  resources = [var.bucket_arns["raw"], "${var.bucket_arns["raw"]}/*"]
}''',
 "The dlt job can read and write the raw bucket and nothing else. A bug in ingest cannot damage the marts."),
  ("main.tf",
'''# dagster role
statement {
  sid       = "PassOnlyPipelineRoles"
  actions   = ["iam:PassRole"]
  resources = [aws_iam_role.ingest.arn, aws_iam_role.transform.arn, aws_iam_role.execution.arn]
}''',
 "Dagster starts tasks and gives each one a role. This limits it to the two pipeline roles, so Dagster cannot start a task with more power than those."),
  ("main.tf",
'''condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = ["repo:${var.github_repo}:ref:refs/heads/main", "repo:${var.github_repo}:environment:prod"]
}''',
 "GitHub Actions signs in with a short-lived token instead of stored keys. This condition only accepts tokens from the main branch or the protected prod environment of your repository."),
 ]),
("governance", "Governance", "modules/governance",
 "A second lock on the data. IAM says a role may use Athena; Lake Formation says which tables it may see.",
 ["Names the Lake Formation administrators.",
  "Registers the raw and lake buckets so Lake Formation controls access to them.",
  "Grants each role access to whole databases: write for the jobs that build them, read-only for the jobs and people that use them."],
 [("main.tf",
'''writers = {
  ingest_raw        = { role = var.task_role_arns["ingest"], db = local.db["raw"], location = "raw" }
  transform_staging = { role = var.task_role_arns["transform"], db = local.db["staging"], location = "lake" }
  transform_mart    = { role = var.task_role_arns["transform"], db = local.db["mart"], location = "lake" }
}''',
 "The whole access model in three lines: which role writes which layer. The readers list next to it works the same way: transform reads raw, and Metabase and analysts read mart."),
  ("main.tf",
'''resource "aws_lakeformation_permissions" "reader_tables" {
  for_each    = local.readers
  principal   = each.value.role
  permissions = ["SELECT", "DESCRIBE"]
  table {
    database_name = each.value.db
    wildcard      = true
  }
}''',
 "Turns each reader line into a grant: SELECT on every table in that database (<code>wildcard = true</code>), including tables dbt creates later."),
 ]),
("compute", "Compute", "modules/compute",
 "The things that run: containers, the database behind Dagster and Metabase, and the front door.",
 ["An ECS cluster on Fargate (no servers to manage).",
  "Long-running services: Dagster's web UI and scheduler, and Metabase.",
  "Run-once task definitions for ingest (dlt) and transform (Soda and dbt), started by Dagster for each run.",
  "Postgres 16 on RDS for Dagster's run history and Metabase's settings, in the data subnets.",
  "A load balancer that makes everyone sign in before reaching Dagster or Metabase, with AWS WAF in front."],
 [("alb.tf",
'''action {
  type  = "authenticate-oidc"
  order = 1
  authenticate_oidc {
    issuer    = var.oidc.issuer
    client_id = var.oidc.client_id
    # ... endpoints and secret trimmed
  }
}

action {
  type             = "forward"
  order            = 2
  target_group_arn = aws_lb_target_group.this[each.key].arn
}''',
 "Two steps for every request to metabase.&lt;domain&gt; or dagster.&lt;domain&gt;. First, sign in with your identity provider. Only then is the request passed to the container."),
  ("ecs.tf",
'''resource "aws_ecs_task_definition" "pipeline" {
  for_each      = { ingest = 1024, transform = 2048 }
  family        = "${var.name}-${each.key}"
  cpu           = each.value
  memory        = each.value * 4
  task_role_arn = var.task_role_arns[each.key]
  # ... image, logs and secrets trimmed
}''',
 "One block, two task definitions. Ingest gets 1 vCPU and 4 GB, transform gets 2 vCPU and 8 GB, and each gets its own role from the permissions module."),
  ("database.tf",
'''resource "aws_db_instance" "this" {
  engine                      = "postgres"
  engine_version              = "16"
  manage_master_user_password = true
  storage_encrypted           = true
  multi_az                    = var.db_multi_az
  publicly_accessible         = false
  deletion_protection         = var.deletion_protection
  # ... size, backups and logging trimmed
}''',
 "The metadata database. AWS creates and rotates its password, so no password appears in the code. It is encrypted, unreachable from the internet, and has a standby copy in prod."),
 ]),
("stack", "The stack", "live",
 "The one folder you run. It joins the modules together and picks the layout.",
 ["<code>main.tf</code> calls each module and passes one module's outputs into the next.",
  "<code>prod.tfvars</code> and <code>learning.tfvars</code> hold the switches that make the two layouts.",
  "<code>tests/plan.tftest.hcl</code> plans both layouts against a fake AWS, so the code is checked without an account."],
 [("main.tf",
'''module "iam" {
  source = "../modules/iam"

  name                = local.name
  bucket_arns         = module.storage.bucket_arns
  kms_key_arns        = module.storage.kms_key_arns
  glue_database_names = module.storage.glue_database_names
  athena_workgroup    = module.storage.athena_workgroup
  bus_arn             = module.events.bus_arn
  queue_arns          = module.events.queue_arns
  github_repo         = var.github_repo
}''',
 "How modules connect. <code>module.storage.bucket_arns</code> is an output of the storage module, handed to the permissions module as an input. Terraform works out the build order from these references."),
  ("learning.tfvars",
'''environment             = "learning"
az_count                = 2
single_nat_gateway      = true
enable_network_firewall = false
interface_endpoints     = []
db_multi_az             = false
deletion_protection     = false''',
 "The cheap layout is just different answers to the same questions. The prod file says the opposite for each line, so the two never drift apart."),
  ("shell",
'''cd live
terraform init -backend-config=backend-prod.hcl
terraform plan  -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars''',
 "How it would be run. <code>plan</code> shows what would change and touches nothing; <code>apply</code> builds it. None of this has been run."),
 ]),
]

KW = re.compile(r'^(\s*)(resource|data|variable|output|module|locals|statement|condition|action|rule|target|table|terraform)\b')
STR = re.compile(r'"(?:[^"\\\n]|\\.)*"')

def hl(code):
    out_lines = []
    for line in code.split("\n"):
        # split off a trailing comment (only when the # is not inside a string)
        body, com = line, ""
        m = re.search(r'\s#\s.*$|^\s*#.*$', line)
        if m and line[:m.start()].count('"') % 2 == 0:
            body, com = line[:m.start()], line[m.start():]
        e = html.escape(body, quote=False)
        e = STR.sub(lambda mm: f'<span class="s">{mm.group(0)}</span>', e)
        e = KW.sub(lambda mm: f'{mm.group(1)}<span class="k">{mm.group(2)}</span>', e)
        if com:
            e += f'<span class="c">{html.escape(com, quote=False)}</span>'
        ind = len(line) - len(line.lstrip(" "))
        e = e[ind:] if e.startswith(" " * ind) else e
        # one block per line; a long line wraps with a hanging indent
        out_lines.append(f'<span class="ln" style="--i:{ind}ch">{e or "&#8203;"}</span>')
    return "".join(out_lines)

tabs_html, panels_html = [], []
for i, (tid, label, folder, intro, builds, chunks) in enumerate(TABS):
    sel = "false"
    tabs_html.append(f'<button role="tab" id="tab-{tid}" aria-controls="p-{tid}" aria-selected="{sel}" data-tab="{tid}">{label}</button>')
    rows = []
    for f, code, note in chunks:
        path = f if f == "shell" else f"{folder}/{f}"
        rows.append(f'''<div class="ex">
  <div class="code"><div class="file">{html.escape(path)}</div><pre><code>{hl(code)}</code></pre></div>
  <p class="why">{note}</p>
</div>''')
    nxt = TABS[i+1] if i + 1 < len(TABS) else None
    nav = f'<button class="next" data-tab="{nxt[0]}">Next: {nxt[1]} →</button>' if nxt else ''
    lis = "".join(f"<li>{b}</li>" for b in builds)
    panels_html.append(f'''<section role="tabpanel" id="p-{tid}" aria-labelledby="tab-{tid}" class="panel" hidden>
  <div class="panel-head">
    <h2>{label}</h2>
    <p class="lede">{intro}</p>
    <p class="path">Folder: <code>terraform/{folder}/</code></p>
  </div>
  <div class="builds"><h3>What it builds</h3><ul>{lis}</ul></div>
  <h3>The key code, explained</h3>
  {''.join(rows)}
  {nav}
</section>''')

tpl = (pathlib.Path(__file__).parent / "tf_template.html").read_text()
out.write_text(tpl.replace("{{TABS}}", "\n".join(tabs_html)).replace("{{PANELS}}", "\n".join(panels_html)))
print("tabs", len(TABS))
