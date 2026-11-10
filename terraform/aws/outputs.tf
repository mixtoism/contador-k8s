output "url" {
  description = "La página del contador"
  value       = aws_apigatewayv2_stage.defecto.invoke_url
}

output "funcion" {
  value = aws_lambda_function.contador.function_name
}

output "tabla" {
  value = aws_dynamodb_table.contador.name
}

output "bedrock" {
  value = local.con_ia ? var.modelo_bedrock : "desactivado"
}

output "rutas" {
  value = sort(keys(aws_apigatewayv2_route.rutas))
}

output "logs" {
  value = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
}
