output "load_balancer_ip" {
  description = "Global anycast IP — point your DNS A record here"
  value       = module.api_cdn.load_balancer_ip
}
