variable "region" {
  description = "AWS region for the app host, database and load balancer. Pick one where the instance_type and db_instance_class exist."
  type        = string
}

variable "domain_name" {
  description = "Public hostname users open, for example app.example.com. Must live in the Route 53 hosted zone below."
  type        = string
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone that contains domain_name. Used for certificate validation and the alias record."
  type        = string
}

variable "instance_type" {
  description = "Graviton instance for the Docker host. The published images are multi-arch, so arm64 needs no special tag."
  type        = string
  default     = "m7g.xlarge"
}

variable "root_volume_size_gb" {
  type    = number
  default = 30
}

variable "data_volume_size_gb" {
  description = "gp3 volume mounted at /var/lib/docker. Holds bot homes, uploaded files and container images."
  type        = number
  default     = 200
}

variable "data_volume_iops" {
  type    = number
  default = 6000
}

variable "data_volume_throughput_mbps" {
  type    = number
  default = 250
}

variable "db_instance_class" {
  type    = string
  default = "db.m7g.large"
}

variable "db_allocated_storage_gb" {
  type    = number
  default = 50
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  type    = bool
  default = true
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "rakazo_repo" {
  description = "Public GitHub repository (owner/name) the host downloads compose files and helper scripts from. Set it to your fork if you deploy from one."
  type        = string
  default     = "elie222/rakazo"
}

variable "rakazo_ref" {
  description = "Git ref of rakazo_repo the host downloads compose files and helper scripts from. Pin a release tag or commit for reproducible deploys."
  type        = string
  default     = "main"
}

variable "rakazo_image_tag" {
  description = "Tag for the published app and computer images. Pin a vX.Y.Z release when you want a fixed version."
  type        = string
  default     = "edge"
}

variable "signup_allowlist" {
  description = "Comma-separated emails or @domains allowed to register, written to SIGNUP_ALLOWLIST. Set it before the first start: the first account to register becomes the deployment owner, and the site is public."
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Set to use Amazon Bedrock as the default model through the instance role, for example an inference profile id. Empty disables Bedrock and grants no Bedrock permissions."
  type        = string
  default     = ""
}

variable "bedrock_resource_arns" {
  description = "Bedrock resources the instance role may invoke. Empty allows every foundation model and inference profile in the account and region; narrow it to the models you use."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
