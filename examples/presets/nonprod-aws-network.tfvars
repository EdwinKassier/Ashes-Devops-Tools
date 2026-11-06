# Cost overlay for NON-PRODUCTION envs/aws/network (~USD 800/month saving).
# DO NOT use for production: removes inline traffic inspection and cross-AZ redundancy.
az_count                = 2 # minimum: Route 53 Resolver endpoints need two AZs
enable_network_firewall = false
