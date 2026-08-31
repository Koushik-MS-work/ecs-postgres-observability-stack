terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # ---------------------------------------------------------------------------
  # Remote state management.
  #
  # The S3 bucket and DynamoDB table referenced here are NOT created by this
  # configuration (Terraform cannot safely manage the backend that stores its
  # own state). Create them once, out of band, before running `terraform init`:
  #
  #   aws s3api create-bucket --bucket <your-tfstate-bucket> --region us-east-1
  #   aws s3api put-bucket-versioning --bucket <your-tfstate-bucket> \
  #       --versioning-configuration Status=Enabled
  #   aws s3api put-bucket-encryption --bucket <your-tfstate-bucket> \
  #       --server-side-encryption-configuration \
  #       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  #   aws dynamodb create-table --table-name terraform-locks \
  #       --attribute-definitions AttributeName=LockID,AttributeType=S \
  #       --key-schema AttributeName=LockID,KeyType=HASH \
  #       --billing-mode PAY_PER_REQUEST
  #
  # Fill in real values via `terraform init -backend-config=backend-<env>.hcl`
  # (see backend-staging.hcl.example / backend-production.hcl.example) since
  # backend blocks cannot reference input variables.
  # ---------------------------------------------------------------------------
  backend "s3" {
    # bucket         = "my-org-tfstate-bucket"
    # key            = "devops-project/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "terraform-locks"
    # encrypt        = true
  }
}
