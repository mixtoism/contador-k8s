output "url" {
  value = aws_apigatewayv2_stage.defecto.invoke_url
}

output "logs" {
  value = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
}
