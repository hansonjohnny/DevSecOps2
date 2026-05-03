terraform {
  backend "s3" {
    bucket         = "cloud-native-buckettt" # must be globally unique
    key            = "todo-app/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true                         # encrypts state file at rest
    dynamodb_table = "cloud-native-dynamodb-lock" # must exist before terraform init
  }
}
