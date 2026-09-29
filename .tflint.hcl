plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  # Dependabot no actualiza esta version; subirla a mano
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
