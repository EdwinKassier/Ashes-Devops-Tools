package terraform.policies.aws_sg_no_public_admin_ports_test

import rego.v1

import data.terraform.policies.aws_sg_no_public_admin_ports as p

one(type, after) := {"plan": {"resource_changes": [{
	"address": sprintf("%s.x", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}]}}

sg(rule) := one("aws_security_group", {"ingress": [rule]})

test_https_from_world_passes if {
	count(p.deny) == 0 with input as sg({"protocol": "tcp", "from_port": 443, "to_port": 443, "cidr_blocks": ["0.0.0.0/0"]})
}

test_ssh_from_private_cidr_passes if {
	count(p.deny) == 0 with input as sg({"protocol": "tcp", "from_port": 22, "to_port": 22, "cidr_blocks": ["10.0.0.0/8"]})
}

test_ssh_from_world_fails if {
	count(p.deny) == 1 with input as sg({"protocol": "tcp", "from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]})
}

test_port_range_covering_rdp_fails if {
	count(p.deny) == 1 with input as sg({"protocol": "tcp", "from_port": 3000, "to_port": 4000, "ipv6_cidr_blocks": ["::/0"]})
}

test_all_protocols_from_world_fails_both_ports if {
	count(p.deny) == 2 with input as sg({"protocol": "-1", "from_port": 0, "to_port": 0, "cidr_blocks": ["0.0.0.0/0"]})
}

test_udp_22_passes if {
	count(p.deny) == 0 with input as sg({"protocol": "udp", "from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]})
}

test_sg_rule_ingress_fails if {
	count(p.deny) == 1 with input as one("aws_security_group_rule", {"type": "ingress", "protocol": "tcp", "from_port": 3389, "to_port": 3389, "cidr_blocks": ["0.0.0.0/0"]})
}

test_sg_rule_egress_passes if {
	count(p.deny) == 0 with input as one("aws_security_group_rule", {"type": "egress", "protocol": "-1", "from_port": 0, "to_port": 0, "cidr_blocks": ["0.0.0.0/0"]})
}

test_vpc_ingress_rule_fails if {
	count(p.deny) == 1 with input as one("aws_vpc_security_group_ingress_rule", {"ip_protocol": "tcp", "from_port": 22, "to_port": 22, "cidr_ipv4": "0.0.0.0/0"})
}

test_vpc_ingress_rule_all_traffic_fails if {
	count(p.deny) == 2 with input as one("aws_vpc_security_group_ingress_rule", {"ip_protocol": "-1", "from_port": null, "to_port": null, "cidr_ipv6": "::/0"})
}

test_vpc_ingress_rule_from_sg_passes if {
	count(p.deny) == 0 with input as one("aws_vpc_security_group_ingress_rule", {"ip_protocol": "tcp", "from_port": 22, "to_port": 22, "referenced_security_group_id": "sg-1"})
}
