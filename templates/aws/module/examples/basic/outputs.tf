output "name" {
  description = "The name of the SSM parameter created by the module"
  value       = module.example.name
}

output "arn" {
  description = "The ARN of the SSM parameter created by the module"
  value       = module.example.arn
}
