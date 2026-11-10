output "url_beanstalk" {
  description = "El contador en Elastic Beanstalk (ALB → instancias EC2)"
  value       = "http://${aws_elastic_beanstalk_environment.this.cname}"
}

output "url_lambda" {
  description = "El contador en Lambda (API Gateway → función)"
  value       = aws_apigatewayv2_stage.defecto.invoke_url
}

output "redis" {
  description = "Endpoint de ElastiCache que comparten los dos"
  value       = "${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "plataforma" {
  value = data.aws_elastic_beanstalk_solution_stack.node.name
}

output "logs_lambda" {
  value = "aws logs tail ${aws_cloudwatch_log_group.lambda.name} --follow"
}
