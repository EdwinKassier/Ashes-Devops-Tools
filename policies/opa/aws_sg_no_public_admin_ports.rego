# MANDATORY: no security-group ingress from 0.0.0.0/0 or ::/0 that reaches
# SSH (22) or RDP (3389). Covers inline aws_security_group ingress blocks,
# aws_security_group_rule (type = ingress) and aws_vpc_security_group_ingress_rule.
# Use SSM Session Manager / Fleet Manager instead of open admin ports.
package terraform.policies.aws_sg_no_public_admin_ports

import rego.v1

import data.terraform.lib

admin_ports := {22, 3389}

world_v4 := "0.0.0.0/0"

world_v6 := "::/0"

# Protocol reaches TCP ("-1"/"all" = every protocol and port).
all_protocols(p) if lower(sprintf("%v", [p])) in {"-1", "all"}

tcp(p) if lower(sprintf("%v", [p])) in {"tcp", "6"}

# Every port is reachable when all protocols are allowed.
exposes(protocol, _, _, _) if all_protocols(protocol)

exposes(protocol, from, to, port) if {
	tcp(protocol)
	is_number(from)
	is_number(to)
	from <= port
	port <= to
}

# Normalised ingress rules: {address, protocol, from, to, cidrs}.
rules contains r if {
	some rc in lib.written_of_type("aws_security_group")
	some rule in object.get(rc.change.after, "ingress", [])
	r := {
		"address": rc.address,
		"protocol": rule.protocol,
		"from": rule.from_port,
		"to": rule.to_port,
		"cidrs": array.concat(lib.as_list(object.get(rule, "cidr_blocks", null)), lib.as_list(object.get(rule, "ipv6_cidr_blocks", null))),
	}
}

rules contains r if {
	some rc in lib.written_of_type("aws_security_group_rule")
	rc.change.after.type == "ingress"
	a := rc.change.after
	r := {
		"address": rc.address,
		"protocol": a.protocol,
		"from": a.from_port,
		"to": a.to_port,
		"cidrs": array.concat(lib.as_list(object.get(a, "cidr_blocks", null)), lib.as_list(object.get(a, "ipv6_cidr_blocks", null))),
	}
}

rules contains r if {
	some rc in lib.written_of_type("aws_vpc_security_group_ingress_rule")
	a := rc.change.after
	r := {
		"address": rc.address,
		"protocol": a.ip_protocol,
		"from": object.get(a, "from_port", 0),
		"to": object.get(a, "to_port", 65535),
		"cidrs": [c | some k in ["cidr_ipv4", "cidr_ipv6"]; c := object.get(a, k, null); c != null],
	}
}

deny contains msg if {
	some r in rules
	some cidr in r.cidrs
	cidr in {world_v4, world_v6}
	some port in admin_ports
	exposes(r.protocol, r.from, r.to, port)
	msg := sprintf("%s: ingress from %s reaches admin port %d", [r.address, cidr, port])
}
