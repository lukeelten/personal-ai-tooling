---
name: helm-expert
description: Generate production-ready Helm charts with hardened security by default. Use this skill whenever the user needs to create or scaffold a Helm chart, whether they mention it explicitly or are describing Kubernetes deployments that need packaging. The skill ensures security best practices including non-root users, read-only filesystems, network policies, RBAC, Pod Security Standards, and resource limits are all built in from the start. Even if the user just says "I need to deploy X to Kubernetes", use this skill to generate a proper Helm chart with hardened defaults.
---

# Generating Security-Hardened Helm Charts

This skill generates production-ready Helm charts with security hardening as the foundation, not an afterthought. All generated charts default to:

- Non-root container users with minimal Linux capabilities
- Read-only root filesystems (with ephemeral scratch space where needed)
- Resource requests and limits (CPU, memory)
- Network policies (restrict ingress/egress by default)
- RBAC resources (ServiceAccount, Role/ClusterRole, RoleBinding)
- Pod Security Standards compliance
- Health checks (livenessProbe, readinessProbe)
- Image pull policies and security contexts

## Understanding the user's intent

The user may describe a Kubernetes workload in many ways:

- "I need a Helm chart for my Node.js microservice"
- "How do I package my database backup job for Kubernetes?"
- "Create a helm chart that deploys a web app with a database sidecar"
- "I have a Docker image, help me deploy it to our cluster"
- Describing a specific application without using the word "Helm"

In all cases, you should generate a Helm chart using this skill, not just hand off generic Kubernetes manifests. The chart should be complete and immediately usable.

## Chart structure and scope

**What to generate:**
- `Chart.yaml` — metadata (name, version, description, appVersion)
- `values.yaml` — all configurable parameters, with sensible defaults
- `templates/` directory with:
  - `deployment.yaml` or `statefulset.yaml` (depending on workload)
  - `service.yaml`
  - `serviceaccount.yaml`
  - `role.yaml` and `rolebinding.yaml` (or clusterrole/clusterrolebinding if needed)
  - `_helpers.tpl` — shared template functions
  - `NOTES.txt` — post-install instructions
  - `configmap.yaml` (if config files are needed)
  - `ingress.yaml` (if the app needs external access)
  - `networkpolicy.yaml` (always include, even as a basic allow-all that users can tighten)
  - `hpa.yaml` (optional; only if the user mentions scaling)
  - `pdb.yaml` (optional; only if the user mentions high availability)

**What not to generate:**
- Tests or validation scripts (the user said no unit tests)
- Kustomize overlays or ArgoCD configurations (unless explicitly asked)
- Helm hooks or custom resource definitions (unless the workload requires them)

## Security-hardened defaults

Every generated template must include these security practices:

### SecurityContext (Pod and Container level)

```yaml
# Pod-level (if applicable)
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 3000
  fsGroup: 2000
  seccompProfile:
    type: RuntimeDefault

# Container-level (always)
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
```

**Important:** If the application needs to write to the filesystem (logs, temp files), add an `emptyDir` volume for `/tmp` or wherever needed. Never make this writable to `root` — use the Pod `fsGroup` and container `runAsUser`/`runAsGroup` to ensure the app user can write to it. Document this in comments.

### Resource management

```yaml
resources:
  requests:
    cpu: 100m        # Adjust based on workload type
    memory: 128Mi     # Adjust based on workload type
  limits:
    cpu: 500m
    memory: 512Mi
```

Requests and limits are parameterized in `values.yaml` with sensible defaults. The user can override. Never leave them unset.

### Health checks

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

Adjust the path, port, and initial delay based on the application type. If the app doesn't expose HTTP, ask the user or use a tcpSocket or exec probe instead.

### Image pulling

```yaml
imagePullPolicy: IfNotPresent  # or Always for latest tags
```

Parameterize in values.yaml. Default to `IfNotPresent` for released versions, `Always` if using a `latest` tag.

### RBAC

Always generate:
- A `ServiceAccount` (not using `default`)
- A `Role` (or `ClusterRole` if needed) with minimal permissions
- A `RoleBinding` to bind them together
- Set `automountServiceAccountToken: false` in Pod spec unless the app needs it

The Role should only grant verbs the application actually needs. For example:

```yaml
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
    resourceNames: []  # Leave empty for all; restrict if needed
```

### Network policies

Always include a `NetworkPolicy`. At minimum:

```yaml
policyTypes:
  - Ingress
  - Egress

ingress:
  - from:
      - podSelector:
          matchLabels: {}  # This allows nothing by default; user can add selectors
    ports:
      - protocol: TCP
        port: 8080

egress:
  - to:
      - podSelector: {}
    ports:
      - protocol: TCP
        port: 53  # DNS
      - protocol: UDP
        port: 53
  - to:
      - podSelector: {}
    ports:
      - protocol: TCP
        port: 443  # HTTPS outbound
```

Add comments explaining that the user should tighten `from`/`to` selectors based on their cluster topology.

### Pod Security Standards

If generating for Kubernetes 1.25+, add labels to the namespace or Pod template to enforce PSS restricted level (or baseline if the app requires it). Document this:

```yaml
# Pod template labels (if applying Pod Security Standards)
labels:
  pod-security.kubernetes.io/enforce: restricted
```

Explain in NOTES.txt that the user may need to adjust this if the application can't comply with restricted.

## values.yaml structure

Organize values clearly with comments explaining defaults and what each section controls:

```yaml
# Global settings
replicaCount: 1

# Image configuration
image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: "1.24"  # Overrides Chart.appVersion

# Container port and service
service:
  type: ClusterIP
  port: 80
  targetPort: 8080

# Resource limits and requests
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Horizontal Pod Autoscaler (optional)
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

# Pod Disruption Budget (optional)
podDisruptionBudget:
  enabled: false
  minAvailable: 1

# Ingress configuration (optional)
ingress:
  enabled: false
  className: "nginx"
  hosts:
    - host: example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []

# Environment variables and config
env: {}
  # KEY: value

# Node affinity and tolerations
affinity: {}
tolerations: []

# Additional volumes and volumeMounts
volumes: []
volumeMounts: []
```

## _helpers.tpl patterns

Include common template helpers:

```
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mychart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "mychart.labels" -}}
helm.sh/chart: {{ include "mychart.chart" . }}
{{ include "mychart.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mychart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
```

## Deployment vs. StatefulSet

- Use **Deployment** for stateless applications (web servers, APIs, worker processes that can restart)
- Use **StatefulSet** for stateful workloads (databases, distributed systems, anything with persistent identity)

Ask the user or infer from context. If uncertain, default to Deployment.

## When to ask the user for clarification

- **Port and protocol:** What port does the app listen on? HTTP/HTTPS/gRPC?
- **Health checks:** Does the app expose a health endpoint? What's the path?
- **Persistence:** Does the app need a PersistentVolumeClaim?
- **Environment-specific config:** Should values differ across dev/staging/prod?
- **Sidecar or init containers:** Does the app need companions?
- **Secrets:** Does the app need mounted secrets (TLS, API keys)?

For missing details, provide reasonable defaults and add comments noting what the user should review and customize.

## Validation and output

Once the chart is generated:

1. **Show the user the full structure** — list all files that were created
2. **Explain the security choices** — briefly call out what was hardened and why
3. **Provide next steps** — tell them how to:
   - `helm lint` the chart to validate syntax
   - `helm template <release-name> .` to preview manifests
   - `helm install <release-name> . --dry-run --debug` to see what will deploy
   - `helm install <release-name> .` to actually deploy

4. **Document any custom choices** — if the user provided specific details, note where they're reflected in the chart

## Example: Typical flow

**User says:** "I have a Node.js API running on port 3000. It needs to call a database and expose metrics on /metrics. I want it to scale to at least 2 replicas."

**You should:**
1. Confirm: "I'll create a Deployment with HPA for scaling, Ingress for HTTP access, NetworkPolicy, RBAC, and security hardening. The Pod will run as non-root with a read-only filesystem, and I'll add an emptyDir for logs. Should I assume it needs to write to `/tmp` or elsewhere?"
2. Generate the chart with:
   - Deployment (2 replicas, scaling to max 10)
   - Service (port 3000)
   - ServiceAccount + Role + RoleBinding
   - NetworkPolicy (allow DNS, allow outbound to database network)
   - HPA (minReplicas: 2, maxReplicas: 10, CPU-based scaling)
   - Health checks pointing to `/metrics` and a `/health` endpoint (or ask the user)
   - Security context (non-root, read-only root filesystem, emptyDir for /tmp)
3. Show the chart structure and explain the security settings
4. Tell them how to test and deploy it

## Output format

Generate all files as text output or save them to the filesystem if you have access to it. Organize them in the chart directory structure:

```
mychart/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   ├── role.yaml
│   ├── rolebinding.yaml
│   ├── networkpolicy.yaml
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   └── ingress.yaml
```

Make sure the chart is complete, self-contained, and ready to use immediately.
