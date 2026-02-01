terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# --- PROVIDERS ---

provider "aws" {
  alias   = "management"
  region  = "us-east-1"
  profile = "management-profile"
}

provider "aws" {
  alias   = "production"
  region  = "us-east-1"
  profile = "production-profile"
}

provider "aws" {
  alias   = "development"
  region  = "us-east-1"
  profile = "development-profile"
}