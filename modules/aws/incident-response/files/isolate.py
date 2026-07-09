"""Incident-response isolation handler (scaffold).

Triggered by EventBridge on high-severity GuardDuty findings. This is a
deliberate scaffold: it logs the finding and returns success. Extend it to
attach the quarantine security group to the flagged EC2 instance and, if
required, share an EBS snapshot with the forensics account.

Runtime: python3.12 (stdlib only, no third-party dependencies).
"""

import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def handler(event, context):
    """Log the GuardDuty finding and (stub) isolate the flagged instance."""
    logger.info("Received GuardDuty finding event: %s", json.dumps(event))

    detail = event.get("detail", {}) if isinstance(event, dict) else {}
    resource = detail.get("resource", {})
    instance = resource.get("instanceDetails", {}).get("instanceId")

    if instance:
        logger.info(
            "Would attach quarantine security group to instance %s", instance
        )
    else:
        logger.info("No instance id in finding; nothing to isolate")

    # TODO(incident-response): attach quarantine SG to the instance and,
    # for forensics, share the EBS snapshot with the forensics account.
    return {"ok": True}
