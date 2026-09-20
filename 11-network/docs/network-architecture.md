# Network architecture

## Topology

```
                            internet
                                │
                    ┌───────────┴────────────┐
                    │  only from allowed_cidr │   (operator IP /32)
                    └───────────┬────────────┘
                                │
╔═══════════════ VPC main  10.42.0.0/16 ═══════════╪═══════════════════════════╗
║                                                   │                           ║
║   ┌──────────── public-a  10.42.1.0/24 (AZ a) ───┴────────────────────────┐  ║
║   │                                                                        │  ║
║   │   web 10.42.1.10        monitoring            nat                      │  ║
║   │   nginx :80             Grafana :3000         src/dest check OFF       │  ║
║   │   node_exporter :9100   Prometheus :9090      iptables MASQUERADE      │  ║
║   │        ▲                      │                     ▲                  │  ║
║   │        └──── :9100 from ──────┘                     │                  │  ║
║   │              monitoring SG only                     │                  │  ║
║   └─────────────────────────────────────────────────────┼──────────────────┘  ║
║        rt: 0.0.0.0/0 → IGW                              │                     ║
║        NACL: 22/80/3000/9090 from operator IP,          │ default route       ║
║              VPC + peer CIDR, ephemeral return          │ of the private tier ║
║                                                         │                     ║
║   ┌──────────── public-b  10.42.2.0/24 (AZ b) ──────────┼──────────────────┐  ║
║   │   (reserved — lets the stack go multi-AZ later)     │                  │  ║
║   └─────────────────────────────────────────────────────┼──────────────────┘  ║
║                                                         │                     ║
║   ┌──────────── private-a 10.42.10.0/24 (AZ a) ─────────┴──────────────────┐  ║
║   │                                                                        │  ║
║   │   private-host 10.42.10.10                                             │  ║
║   │   no public IP · no IGW route · strongSwan IPsec endpoint              │  ║
║   │                                                                        │  ║
║   └──────────────────────────────┬─────────────────────────────────────────┘  ║
║        rt: 0.0.0.0/0 → NAT ENI   │  10.43.0.0/16 → peering                    ║
║        NACL: inbound from VPC + peer CIDR only, ephemeral return              ║
║                                  │                                            ║
║   S3 gateway endpoint ───────────┤  (S3 traffic never leaves the AWS network) ║
╚══════════════════════════════════╪════════════════════════════════════════════╝
                                   │
                          VPC peering connection
                     (private route, never the internet)
                                   │
╔══════════════════════════════════╪════════════════════════════════════════════╗
║   VPC peer  10.43.0.0/16         │                                            ║
║   ┌──────── peer-subnet 10.43.1.0/24 ─────────────────────────────────────┐   ║
║   │   peer-host 10.43.1.10 · strongSwan IPsec endpoint                    │   ║
║   └───────────────────────────────────────────────────────────────────────┘   ║
║        rt: 10.42.0.0/16 → peering                                             ║
╚═══════════════════════════════════════════════════════════════════════════════╝

        private-host ◄══ IPsec transport mode, IKEv2, AES-256/SHA-256 ══► peer-host
                         (encrypts the payload riding the peering link)
```

## IP address plan

| Range | Purpose | AZ | Public? |
|---|---|---|---|
| `10.42.0.0/16` | VPC main | — | — |
| `10.42.1.0/24` | public-a — web, monitoring, NAT | a | yes |
| `10.42.2.0/24` | public-b — reserved for growth | b | yes |
| `10.42.10.0/24` | private-a — private workloads | a | no |
| `10.43.0.0/16` | VPC peer ("remote network") | — | — |
| `10.43.1.0/24` | peer-subnet | a | yes (for bootstrap only) |

Gaps are deliberate: `10.42.3–9` and `10.42.11+` stay free so a database or
cache tier can be added without renumbering anything. The two VPC ranges do
not overlap, which is what makes peering possible at all — overlapping CIDRs
cannot be peered.

## Routing design

| Route table | Destination | Target | Why |
|---|---|---|---|
| public-rt | `10.42.0.0/16` | local | implicit; intra-VPC traffic |
| public-rt | `0.0.0.0/0` | Internet Gateway | public tier needs direct internet |
| public-rt | `10.43.0.0/16` | peering | reach the remote network privately |
| public-rt | S3 prefix list | S3 gateway endpoint | keep S3 traffic off the internet |
| private-rt | `10.42.0.0/16` | local | subnet-to-subnet, no gateway involved |
| private-rt | `0.0.0.0/0` | **NAT instance ENI** | egress without inbound exposure |
| private-rt | `10.43.0.0/16` | peering | private↔remote connectivity |
| private-rt | S3 prefix list | S3 gateway endpoint | same, from the private tier |
| peer-rt | `10.42.0.0/16` | peering | return path — peering is not automatic |

The private subnet is private because of **routing**, not labelling: there is
no route to the Internet Gateway, so no amount of security-group permissiveness
can make an instance there reachable from outside.

## Two layers of filtering, and why both

| | Security Groups | Network ACLs |
|---|---|---|
| Attached to | instance (ENI) | subnet |
| State | **stateful** — replies allowed automatically | **stateless** — every direction needs a rule |
| Rules | allow only | allow **and** deny, evaluated in order |
| Role here | per-workload intent | a floor no instance in the subnet can undercut |

The stateless nature of NACLs is why each list carries an explicit
ephemeral-port (1024–65535) inbound rule. Without it, every outbound request
an instance makes would hang waiting for a reply that the NACL silently drops —
the single most common NACL mistake.

## Rule justification

| Rule | Scope | Justification |
|---|---|---|
| SSH 22 ← operator IP | web, monitoring, NAT | administration; never `0.0.0.0/0` |
| HTTP 80 ← operator IP | web | demo app is not meant to be public |
| Grafana 3000 ← operator IP | monitoring | dashboards are operator-only |
| Prometheus 9090 ← operator IP | monitoring | query UI, operator-only |
| **node_exporter 9100 ← monitoring SG** | web, private | metrics have exactly one legitimate consumer; SG-to-SG means it survives IP changes |
| SSH 22 ← VPC CIDR | private | no public path exists; jump through the web host |
| ICMP ← VPC + peer CIDR | private, web, peer | connectivity testing |
| UDP 500 / 4500, ESP ← VPC CIDR | peer | IKE negotiation and the encrypted payload |
| all ← private subnet CIDR | NAT | it exists to forward that subnet's traffic |
| **egress 443/80/53 only** | all | package repos, registries, DNS — nothing else |
| egress all → VPC + peer CIDR | all | internal traffic is unrestricted by design |

No rule anywhere grants `0.0.0.0/0` on all protocols inbound, and egress is an
explicit allow-list rather than the default open door.

## Monitoring and audit

VPC Flow Logs capture **ACCEPT and REJECT** for every flow into a CloudWatch
log group with 1-day retention (flow logs get expensive quickly). REJECT
records are what make a blocked connection provable after the fact rather than
only at the moment someone runs `curl`.

Every resource above is defined in Terraform, so changes are reviewable as
diffs and `terraform plan -detailed-exitcode` detects drift — which is exactly
what `scripts/change-and-validate.sh` uses to prove a manual change was fully
reverted.

## Known limitations

- **Peering, not a VPN gateway.** A Site-to-Site VPN would cost ~$36/month to
  demonstrate the same thing. Peering keeps traffic on the AWS backbone, and
  the IPsec tunnel on top supplies the encryption a VPN gateway would provide.
- **PSK authentication.** The pre-shared key is generated at apply time and
  lives in Terraform state and instance user-data. Fine for a demo; production
  belongs on certificates or Secrets Manager.
- **NAT instance, not NAT Gateway.** ~$7.50/month instead of ~$32, at the cost
  of being a single point of failure with no automatic failover. A production
  design would use a managed NAT Gateway per AZ.
- **Single AZ in use.** `public-b` is provisioned but empty; genuine HA would
  need a second NAT and instances spread across both.
