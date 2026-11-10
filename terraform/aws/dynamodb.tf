# El contador: en lugar de Redis, una tabla DynamoDB que se paga por petición.
# Un elemento "visitas" con el total y uno "instancia#<id>" por cada copia de la Lambda.
resource "aws_dynamodb_table" "contador" {
  name         = "contador-${var.entorno}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.entorno == "prod"
  }
}
