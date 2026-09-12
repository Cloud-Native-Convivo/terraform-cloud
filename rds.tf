# Oracle Database Free 23ai — sidecar containers en cada task de microservicio de dominio.
# No hay RDS: cada microservicio (ms-espacios-comunes, ms-gastos-comunes) corre con su
# propia instancia Oracle como sidecar en el mismo task (localhost:1521).
# Ver task_definitions.tf → resource "aws_ecs_task_definition" "domain".
# Secrets (ORACLE_PWD) definidos en secrets.tf.