output "load_balancer_ip" {
  description = "Internal VIP of the load balancer"
  value       = module.internal_lb.ip_address
}
