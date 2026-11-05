# Cost overlay for NON-PRODUCTION envs/aws/network (~USD 800/month saving).
# DO NOT use for production: removes inline traffic inspection and cross-AZ redundancy.
az_count                = 1
enable_network_firewall = false
