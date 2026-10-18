data "aws_caller_identity" "current" {}

# Ubuntu 24.04 on arm64: Docker CE from Docker's apt repository satisfies the
# Docker Engine 26+ requirement that bot home volume subpaths need.
data "aws_ssm_parameter" "ubuntu_arm64" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
}

locals {
  bedrock_enabled = var.bedrock_model_id != ""
  bedrock_resource_arns = length(var.bedrock_resource_arns) > 0 ? var.bedrock_resource_arns : [
    "arn:aws:bedrock:*::foundation-model/*",
    "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
  ]
}

resource "aws_iam_role" "app" {
  name_prefix = "rakazo-app-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Shell access goes through Session Manager. There is no SSH port.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "database_secret" {
  name = "read-database-secret"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_iam_role_policy" "bedrock" {
  count = local.bedrock_enabled ? 1 : 0
  name  = "invoke-bedrock"
  role  = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:Converse",
        "bedrock:ConverseStream",
      ]
      Resource = local.bedrock_resource_arns
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name_prefix = "rakazo-app-"
  role        = aws_iam_role.app.name
}

resource "aws_ebs_volume" "data" {
  availability_zone = local.azs[0]
  size              = var.data_volume_size_gb
  type              = "gp3"
  iops              = var.data_volume_iops
  throughput        = var.data_volume_throughput_mbps
  encrypted         = true

  tags = {
    Name     = "rakazo-data"
    Snapshot = "rakazo-data"
  }
}

resource "aws_instance" "app" {
  ami                    = nonsensitive(data.aws_ssm_parameter.ubuntu_arm64.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name
  ebs_optimized          = true

  # Hop limit 2 lets the API container reach the instance role for Bedrock.
  # Bot computers cannot: the egress ruleset installed at boot drops their
  # traffic to link-local and private addresses.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    region           = var.region
    domain_name      = var.domain_name
    rakazo_repo      = var.rakazo_repo
    rakazo_ref       = var.rakazo_ref
    image_tag        = var.rakazo_image_tag
    data_volume_id   = replace(aws_ebs_volume.data.id, "-", "")
    db_address       = aws_db_instance.main.address
    db_secret_arn    = aws_db_instance.main.master_user_secret[0].secret_arn
    signup_allowlist = var.signup_allowlist
    bedrock_model_id = var.bedrock_model_id
  })

  tags = { Name = "rakazo-app" }

  # A new AMI or bootstrap script must not replace the host that owns the data
  # volume. Roll the host deliberately with `terraform apply -replace`.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.app.id
}

resource "aws_iam_role" "dlm" {
  name_prefix = "rakazo-dlm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dlm.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# Daily snapshots of the bot homes and uploads, retained for a week.
resource "aws_dlm_lifecycle_policy" "data" {
  description        = "Daily rakazo data volume snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { Snapshot = "rakazo-data" }

    schedule {
      name = "daily"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 7
      }

      copy_tags = true
    }
  }
}
