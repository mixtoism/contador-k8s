# Sólo existe una de las dos plataformas: concat + one() se queda con la que haya.

output "url" {
  description = "La página del contador"
  value = one(concat(
    [for e in aws_elastic_beanstalk_environment.this : "http://${e.cname}"],
    aws_apigatewayv2_stage.defecto[*].invoke_url,
  ))
}

output "plataforma" {
  value = local.es_beanstalk ? "Elastic Beanstalk (${one(data.aws_elastic_beanstalk_solution_stack.node[*].name)})" : "Lambda + API Gateway"
}

output "redis" {
  description = "Endpoint de ElastiCache"
  value       = "${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "logs" {
  value = one(concat(
    [for e in aws_elastic_beanstalk_environment.this : "aws logs tail /aws/elasticbeanstalk/${e.name}/var/log/web.stdout.log --follow"],
    [for g in aws_cloudwatch_log_group.lambda : "aws logs tail ${g.name} --follow"],
  ))
}
