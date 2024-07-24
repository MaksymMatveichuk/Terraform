resource "null_resource" "docker_packaging" {

  provisioner "local-exec" {
    working_dir = "backend"
    command     = <<EOF
aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.eu-north-1.amazonaws.com && docker build -t backrepository . && docker tag backrepository:latest ${data.aws_caller_identity.current.account_id}.dkr.ecr.eu-north-1.amazonaws.com/backrepository:latest && docker push ${data.aws_caller_identity.current.account_id}.dkr.ecr.eu-north-1.amazonaws.com/backrepository:latest
    EOF
  }

  triggers = {
    "run_at" = timestamp()
  }

}
