# Cuenta AWS Academy Learner Lab: no hay permiso iam:CreateRole ni para adjuntar policies
# propias — Academy da un rol único "LabRole" con permisos ya amplios. Se reusa ese, no se
# crean roles nuevos. Si el proyecto migra a una cuenta AWS normal, volver a crear
# ecsTaskExecutionRole/ecsTaskRole con policies acotadas (AmazonECSTaskExecutionRolePolicy +
# secretsmanager:GetSecretValue) en vez de este data source.

data "aws_iam_role" "lab" {
  name = "LabRole"
}
