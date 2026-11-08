variable "orders_db_password" {
  description = "Initial database password. Set it with TF_VAR_orders_db_password or a TFC sensitive variable; it is never stored in plan or state."
  type        = string
  sensitive   = true
  ephemeral   = true
}
