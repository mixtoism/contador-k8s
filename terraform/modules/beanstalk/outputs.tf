output "url" {
  value = "http://${aws_elastic_beanstalk_environment.this.cname}"
}

output "logs" {
  value = "aws logs tail /aws/elasticbeanstalk/${aws_elastic_beanstalk_environment.this.name}/var/log/web.stdout.log --follow"
}
