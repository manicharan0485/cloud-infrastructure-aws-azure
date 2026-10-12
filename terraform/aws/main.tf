# =============================================================================
# terraform/aws/main.tf
# AWS Infrastructure: VPC, EC2, S3, RDS, IAM
# Author: Manicharan Ravi
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket = "terraform-state-backup-infra"
    key    = "aws/terraform.tfstate"
    region = "eu-central-1"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = var.project_name
    }
  }
}

# ── VPC ────────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# ── S3 Backup Bucket ───────────────────────────────────────────────────────────
resource "aws_s3_bucket" "backup" {
  bucket = "${var.project_name}-backup-${var.environment}"
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

# ── RDS (PostgreSQL) ───────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_security_group" "rds" {
  name   = "${var.project_name}-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "PostgreSQL from VPC only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "main" {
  identifier              = "${var.project_name}-db-${var.environment}"
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = var.db_instance_class
  allocated_storage       = 100
  storage_encrypted       = true
  multi_az                = var.environment == "production"
  publicly_accessible     = false
  deletion_protection     = var.environment == "production"
  skip_final_snapshot     = var.environment != "production"
  backup_retention_period = 30
  backup_window           = "02:00-03:00"
  maintenance_window      = "Mon:03:00-Mon:04:00"
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  username                = var.db_username
  manage_master_user_password = true   # Secrets Manager managed
}

# ── IAM Role for EC2 (least privilege) ────────────────────────────────────────
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_s3_backup" {
  name = "s3-backup-access"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "cloudwatch:GetMetricStatistics"]
        Resource = "*"
      }
    ]
  })
}
