# EKS + ArgoCD GitOps Platform

Terraform project that provisions an Amazon EKS cluster on AWS and bootstraps it with
[Argo CD](https://argo-cd.readthedocs.io/) for GitOps-driven delivery. Argo CD, in turn,
installs the [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs, [kgateway](https://kgateway.dev/)
as the Gateway API implementation (exposed via an AWS Network Load Balancer), and a sample
application (`go-counter-href-10-sites`) pulled from its own Git repository.

Everything after the EKS cluster is created is managed declaratively through Argo CD
`Application`/`AppProject` manifests — Terraform only applies the initial bootstrap
manifests and then hands off control to Argo CD's own sync loop.

## Architecture

```
                         ┌─────────────────────────────────────────────┐
                         │                 AWS Account                 │
                         │                                              │
                         │   ┌───────────────── VPC ─────────────────┐ │
                         │   │  Public subnets   Private subnets      │ │
                         │   │  (NAT GW, NLB)     (EKS nodes)         │ │
                         │   └────────────────────────────────────────┘ │
                         │                     │                        │
                         │           ┌─────────▼─────────┐              │
                         │           │   EKS Cluster      │              │
                         │           │  (EKS Auto Mode /  │              │
                         │           │  compute_config)   │              │
                         │           │                     │              │
                         │           │  ┌───────────────┐  │              │
                         │           │  │   Argo CD     │  │              │
                         │           │  │ (helm_release)│  │              │
                         │           │  └───────┬───────┘  │              │
                         │           │          │ manages   │              │
                         │           │  ┌───────▼───────┐  │              │
                         │           │  │ Gateway API    │ │              │
                         │           │  │ CRDs + kgateway│ │              │
                         │           │  │ (Argo apps)    │ │              │
                         │           │  └───────┬───────┘  │              │
                         │           │          │ routes    │              │
                         │           │  ┌───────▼───────┐  │              │
                         │           │  │ counter-api    │ │              │
                         │           │  │ (Argo app, from│ │              │
                         │           │  │ external repo) │ │              │
                         │           │  └───────────────┘  │              │
                         │           └─────────────────────┘              │
                         └─────────────────────────────────────────────┘
```

**Bootstrap flow (Terraform):**

1. VPC (public + private subnets, single NAT Gateway).
2. EKS cluster in the private subnets, using EKS's managed `compute_config` (Auto Mode
   style, `general-purpose` node pool).
3. Argo CD installed via Helm into the cluster.
4. Gateway API standard CRDs applied, then the kgateway CRDs and kgateway controller
   installed as Argo CD `Application` resources (`kubectl_manifest`).
5. An Argo CD `AppProject` and `Application` are created pointing at an external Git repo
   containing the sample workload; from this point on, Argo CD syncs and reconciles the
   application itself (GitOps hand-off).

## Repository structure

```
.
├── providers.tf                 # Terraform/provider requirements (aws, kubernetes, kubectl, helm)
├── variables.tf                 # Input variables (region, naming, CIDRs, ArgoCD chart, ...)
├── locals.tf                    # Derived naming, CIDRs, AZs, and caller's public IP
├── data.tf                      # Data sources: caller identity, AZs, public IP, EKS auth, CRD docs
├── outputs.tf                   # Post-apply instructions (kubeconfig, ArgoCD login, app access, destroy)
├── 01-vpc.tf                    # VPC module (terraform-aws-modules/vpc)
├── 02-eks.tf                    # EKS module (terraform-aws-modules/eks)
├── 03-argocd.tf                 # Argo CD Helm release
├── 04-ingress-controller.tf     # Gateway API CRDs + kgateway (CRDs and controller) via ArgoCD manifests
├── 05-app-deployment.tf         # ArgoCD AppProject + Application for the sample workload
└── argocd/
    ├── app/
    │   ├── app-project.yaml     # ArgoCD AppProject: go-counter-href-10-sites-project
    │   └── application.yaml     # ArgoCD Application: counter-api (external Git repo source)
    └── kgateway/
        ├── standard-install.yaml # Upstream Gateway API "standard" channel CRDs
        ├── crds-helm.yaml        # ArgoCD Application installing the kgateway-crds Helm chart
        ├── helm.yaml              # ArgoCD Application installing the kgateway controller Helm chart
        └── parameters.yaml        # GatewayParameters: public-facing AWS NLB configuration
```

## Resources deployed

### Networking (`01-vpc.tf`)
- **VPC** (module `terraform-aws-modules/vpc/aws ~> 5`) with 3 public and 3 private
  subnets spread across 3 Availability Zones.
- Single **NAT Gateway** for outbound traffic from private subnets.
- DNS hostnames/support enabled.
- Subnets tagged for Kubernetes/ELB auto-discovery
  (`kubernetes.io/cluster/<cluster>`, `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`).

### EKS cluster (`02-eks.tf`)
- **EKS cluster** (module `terraform-aws-modules/eks/aws ~> 21.3`) deployed into the
  private subnets.
- Public API endpoint access restricted to the operator's current public IP
  (`data.http.my_ip`).
- `compute_config` enabled with the `general-purpose` node pool (EKS-managed compute,
  no self-managed node groups to maintain).
- Cluster creator is automatically granted admin permissions
  (`enable_cluster_creator_admin_permissions`).

### GitOps controller (`03-argocd.tf`)
- **Argo CD** installed via the official Helm chart (`argo-cd`, `argoproj.github.io/argo-helm`)
  into the `argocd` namespace.
- Single-replica configuration for `controller`, `server`, `repoServer`, and
  `applicationSet`; `redis-ha` disabled (suitable for dev/demo, not HA production use).
- Server runs in `insecure` mode (TLS termination expected to happen at the
  Gateway/Load Balancer, not at the Argo CD server pod).

### Ingress / Gateway API (`04-ingress-controller.tf`)
- Upstream **Gateway API standard-channel CRDs** applied directly to the cluster.
- **kgateway CRDs** and **kgateway controller** installed as Argo CD `Application`
  resources (chart source: `cr.kgateway.dev/kgateway-dev/charts`, version `v2.4.3`),
  each with automated `prune`/`selfHeal` sync policies.
- `parameters.yaml` (`GatewayParameters`) provisions the Gateway's Kubernetes `Service`
  as an internet-facing **AWS Network Load Balancer** (`aws-load-balancer-type: external`,
  `nlb-target-type: ip`).

### Application (`05-app-deployment.tf`)
- **AppProject** `go-counter-href-10-sites-project` scoping allowed source repos/destinations.
- **Application** `counter-api`, sourced from
  [`go-counter-href-10-sites`](https://github.com/alvarolinarescabre/go-counter-href-10-sites.git)
  (`deploy/helm/counter-api`, branch `main`), deployed into the `counter-api` namespace
  with automated sync (`prune`, `selfHeal`, `CreateNamespace=true`).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) `>= 1.5` (providers pin `aws ~> 6`, `kubernetes ~> 2`, `kubectl ~> 2.1.3`, `helm ~> 2`)
- An AWS account and credentials configured (env vars, `~/.aws/credentials`, or SSO) with
  permissions to create VPC, EKS, IAM, and ELB/NLB resources.
- [`aws` CLI](https://docs.aws.amazon.com/cli/) v2, used for `eks get-token` auth by the
  Kubernetes/kubectl/Helm providers and for `update-kubeconfig`.
- `kubectl` to interact with the cluster once it is up.
- Outbound internet access from where you run Terraform (used to detect your public IP
  via `https://checkip.amazonaws.com` for restricting the EKS API endpoint).

## Deployment

```bash
# 1. Initialize providers and modules
terraform init

# 2. Review the plan
terraform plan

# 3. Apply (creates VPC, EKS, Argo CD, Gateway API/kgateway, and the ArgoCD Application)
terraform apply
```

> The EKS/kubectl/kubernetes/helm providers depend on the cluster created by
> `module.eks`, so `terraform apply` builds everything in a single run — no need for a
> two-phase apply.

### Post-deploy

On success, the `instructions` output prints the exact commands to run. Summarized:

**1. Configure kubectl:**
```bash
aws eks update-kubeconfig --region <region> --name <cluster_name>
```

**2. Log in to Argo CD:**
```bash
kubectl get ingress -n argocd            # use the ADDRESS of argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d   # initial 'admin' password
```

**3. Reach the sample application:**
```bash
kubectl get httproutes.gateway.networking.k8s.io -n counter-api
# map the returned HOSTNAME(s) to the NLB address in your /etc/hosts
```

### Destroy

```bash
terraform destroy
```

## Variables

| Name                    | Description                          | Default            |
|--------------------------|---------------------------------------|---------------------|
| `region`                | AWS region to deploy resources        | `eu-west-1`         |
| `environment`           | Environment name                      | `dev`               |
| `project_name`          | Project name prefix (naming)          | `chamo`             |
| `cluster_version`       | Kubernetes version for EKS            | `1.35`              |
| `vpc_cidr`              | VPC CIDR block                        | `10.0.0.0/16`       |
| `private_subnets`       | Private subnet CIDR blocks            | `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24` |
| `public_subnets`        | Public subnet CIDR blocks             | `10.0.101.0/24`, `10.0.102.0/24`, `10.0.103.0/24` |
| `argocd_namespace`      | Namespace for Argo CD                 | `argocd`            |
| `argocd_chart_version`  | Argo CD Helm chart version            | `7.8.2`             |

Naming is derived in [locals.tf](locals.tf) as `<project_name>-<environment>`, e.g.
`chamo-dev-vpc`, `chamo-dev-cluster`.

## Outputs

- `instructions` — post-apply cheat sheet with the exact `kubectl`/`aws` commands for
  configuring kubeconfig, retrieving the Argo CD admin password, and reaching the sample
  app through the Gateway/NLB. See [outputs.tf](outputs.tf).

## Notes & considerations

- The EKS API endpoint is restricted to the machine's public IP at apply time
  (`data.http.my_ip`); re-run `terraform apply` if your IP changes and you lose access.
- This setup is intended for **dev/demo** use: Argo CD runs single-replica with Redis HA
  disabled, and the Argo CD server is exposed `insecure` (no TLS) behind the gateway.
- The sample application (`counter-api`) is fetched from an external repository at sync
  time — Terraform does not manage its manifests directly, only the Argo CD
  `Application`/`AppProject` pointing to it.
- kgateway's public NLB is `internet-facing`; adjust
  [argocd/kgateway/parameters.yaml](argocd/kgateway/parameters.yaml) if an internal-only
  load balancer is required.
