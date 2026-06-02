# Helm Charts Hardened Skill

A powerful skill for generating production-ready Helm charts with security hardening by default.

## What This Skill Does

The **helm-charts-hardened** skill generates complete, security-hardened Helm charts for any Kubernetes workload type:

- **Deployments** - Stateless applications with scaling support
- **StatefulSets** - Stateful workloads with persistent storage
- **CronJobs** - Scheduled jobs with Secrets and ConfigMaps
- **Multi-container pods** - Sidecar patterns and complex architectures
- **Multi-environment** - Parameterized charts for dev/staging/production

## When to Use This Skill

Use this skill whenever:
- You need to create a new Helm chart for Kubernetes
- You want security hardening baked in by default
- You're deploying containerized applications
- You need to manage Secrets, ConfigMaps, or persistent storage
- You want to scale applications with HPA
- You need multi-environment (dev/staging/prod) support
- You're deploying scheduled jobs or batch workloads

## Key Features

### Security by Default

Every generated chart includes:
- Non-root user execution (UID 1000+)
- Read-only root filesystems (with emptyDir for writable paths)
- Dropped Linux capabilities (ALL)
- Privilege escalation prevention
- RuntimeDefault seccomp profiles
- Pod security contexts

### Production Patterns

- **RBAC**: ServiceAccount, Roles, RoleBindings for least-privilege access
- **Network Policies**: Restrict ingress/egress traffic by default
- **Health Checks**: Liveness and readiness probes
- **Resource Management**: CPU and memory limits/requests
- **High Availability**: Pod anti-affinity, disruption budgets, autoscaling

### Multi-Workload Support

- **Deployments**: Stateless apps with HPA, Ingress, Service
- **StatefulSets**: Databases and stateful apps with PVCs
- **CronJobs**: Scheduled jobs with proper security
- **Multi-container**: Sidecar patterns with shared volumes

### Environment Management

Generate separate values files for different deployment environments:
- `values-dev.yaml` - Development with minimal resources
- `values-staging.yaml` - Staging with moderate resources  
- `values-prod.yaml` - Production with full HA and security

## What Gets Generated

A complete Helm chart with:

### Core Files
- `Chart.yaml` - Chart metadata and versioning
- `values.yaml` - Base configuration with sensible defaults
- `values-{dev,staging,prod}.yaml` - Environment-specific overrides

### Kubernetes Templates
- Deployment or StatefulSet (depending on workload)
- Service (with optional Ingress)
- ServiceAccount, Role, RoleBinding (RBAC)
- NetworkPolicy (traffic control)
- Secret and ConfigMap (if needed)
- HorizontalPodAutoscaler (if scaling needed)
- PodDisruptionBudget (for HA)

### Documentation
- Comprehensive README with setup instructions
- Architecture documentation with diagrams
- Security hardening explanations
- Examples and troubleshooting guides
- Deployment checklists

## Quick Example

**User asks:**
> "Create a Helm chart for my Node.js API. It listens on port 3000, needs to scale based on CPU, and should run with minimal privileges."

**The skill generates:**
- ✅ Deployment with non-root security context
- ✅ HorizontalPodAutoscaler (2-10 replicas, CPU-based)
- ✅ Service exposing port 3000
- ✅ NetworkPolicy restricting traffic
- ✅ ServiceAccount with minimal RBAC
- ✅ Health checks on `/health` endpoint
- ✅ Read-only filesystem with /tmp emptyDir
- ✅ Complete documentation and examples

## Testing & Quality

The skill was tested across 5 comprehensive scenarios:

1. **Node.js API with HPA** - 10/10 assertions passed ✅
2. **PostgreSQL StatefulSet** - 6/8 assertions passed (RBAC gap noted) ⚠️
3. **Multi-container Sidecar** - 8/8 assertions passed ✅
4. **CronJob Backup Job** - 8/8 assertions passed ✅
5. **Multi-environment App** - 10/10 assertions passed ✅

**Overall**: 95.5% feature completeness on first iteration

## Reference Materials

The skill includes bundled documentation:

### `references/best-practices.md`
Detailed guide covering:
- Chart metadata and structure
- Values organization and naming conventions
- Security context deep dive
- RBAC patterns (Role, ClusterRole, RoleBinding, ClusterRoleBinding)
- Network policy examples and patterns
- Common workload patterns (web app, worker, database, sidecars, init containers)

### `references/template-examples.md`
Reusable template examples:
- Complete Deployment template (with security hardening)
- StatefulSet template (with persistent storage)
- _helpers.tpl functions (name, fullname, labels, selectors)
- Service templates (standard and headless)
- Ingress, HPA, and NetworkPolicy examples

## Limitations

- StatefulSet RBAC generation may need review (minor gap in evaluation)
- For very specialized workloads, some customization may be needed
- No unit tests or Kustomize overlays generated

## How It Works

1. **Understand the workload** - Deployment, StatefulSet, CronJob, etc.
2. **Ask clarifying questions** - Port, protocol, storage needs, environment-specific config
3. **Generate the chart** - Complete with all templates and documentation
4. **Provide guidance** - Explain security choices and how to deploy
5. **Documentation included** - Users can immediately understand and use the chart

## Skill Stats

- **Test coverage**: 5 comprehensive scenarios
- **Assertion pass rate**: 95.5% (42/44)
- **Workload types supported**: Deployment, StatefulSet, CronJob, multi-container
- **Security features**: 10+ hardening controls by default
- **Documentation**: Bundled best-practices and template examples
- **Feature parity**: Matches or exceeds general Helm knowledge

## Getting Help

The skill includes comprehensive reference documentation:
- Read `best-practices.md` for deep dives on security, RBAC, and networking
- Check `template-examples.md` for reusable code snippets
- Review generated charts' documentation for specific workload guidance
