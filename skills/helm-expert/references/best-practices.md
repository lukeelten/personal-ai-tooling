# Helm Best Practices Reference

This document covers production patterns and security considerations for Helm charts.

## Table of Contents

1. [Chart Metadata](#chart-metadata)
2. [Values Organization](#values-organization)
3. [Security Context Deep Dive](#security-context-deep-dive)
4. [RBAC Patterns](#rbac-patterns)
5. [Network Policies](#network-policies)
6. [Common Workload Patterns](#common-workload-patterns)

## Chart Metadata

### Chart.yaml structure

```yaml
apiVersion: v2
name: mychart
description: A Helm chart for deploying My Application
type: application
version: 0.1.0
appVersion: "1.0"
keywords:
  - app
  - kubernetes
maintainers:
  - name: Your Name
    email: your.email@example.com
home: https://github.com/org/repo
sources:
  - https://github.com/org/repo
```

**Key fields:**
- `apiVersion: v2` — Helm 3 format (required)
- `type: application` — for deployable apps (not `library`)
- `version` — chart version (semver)
- `appVersion` — the application version being packaged
- `keywords`, `maintainers`, `home`, `sources` — help with discovery and maintenance

## Values Organization

### Naming conventions

Use camelCase for keys, lowercase for obvious categories:

```yaml
# Top-level categories
replicaCount:
image:
service:
resources:
autoscaling:
ingress:
env:
```

Group related settings under a common parent to avoid shallow, sprawling values.yaml.

### Common sections

**Replica configuration:**
```yaml
replicaCount: 1
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: null
```

**Image control:**
```yaml
image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: "1.24.0"
nameOverride: ""
fullnameOverride: ""
```

**Service exposure:**
```yaml
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
  annotations: {}
```

**Resources (always required):**
```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

**Pod configuration:**
```yaml
nodeSelector: {}
affinity: {}
tolerations: []
podAnnotations: {}
podSecurityContext: {}
securityContext: {}
```

## Security Context Deep Dive

### Pod-level securityContext

Applied to all containers in the Pod. Provides defaults that individual containers can override.

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 3000
  fsGroup: 2000              # File system group (important for mounted volumes)
  seccompProfile:
    type: RuntimeDefault     # Use default seccomp profile
```

**Why each field matters:**
- `runAsNonRoot: true` — Prevents container from running as root (uid 0)
- `runAsUser: 1000` — Runs as unprivileged user (avoid uid 0)
- `runAsGroup: 3000` — Primary group for the user
- `fsGroup: 2000` — Files mounted as volumes inherit this GID; allows the app user to write to them
- `seccompProfile.type: RuntimeDefault` — Use the Kubernetes default seccomp profile (restricts dangerous syscalls)

### Container-level securityContext

Applied only to that container, overrides Pod-level settings where needed.

```yaml
securityContext:
  allowPrivilegeEscalation: false    # Cannot use setuid/setgid
  capabilities:
    drop:
      - ALL                           # Remove all Linux capabilities
  readOnlyRootFilesystem: true        # / is read-only
  runAsNonRoot: true
  runAsUser: 1000
```

**Important:** If `readOnlyRootFilesystem: true` and the app writes to disk:
1. Add an `emptyDir` volume for the writable path
2. Mount it in the container
3. Ensure the Pod `fsGroup` and container `runAsUser` allow the app to write

Example:
```yaml
volumes:
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

The app runs as user 1000, fsGroup is 2000, so the app can write to `/tmp` (owned by group 2000).

### Adjusting for specific workloads

Some apps genuinely need capabilities or privileged access. Examples:

**Requires network namespace:** `NET_ADMIN` for tcpdump, network debugging
```yaml
capabilities:
  drop:
    - ALL
  add:
    - NET_ADMIN
```

**Requires chroot/mount namespace:** `SYS_ADMIN` for cgroup-aware tooling
```yaml
capabilities:
  drop:
    - ALL
  add:
    - SYS_ADMIN
```

**Cannot use read-only root:** Some apps write to `/ `, `/etc`, or system paths. Use:
```yaml
readOnlyRootFilesystem: false
```
And document this as a known limitation. Consider whether the app can be refactored to use `/tmp` or `/var/tmp`.

## RBAC Patterns

### Minimal ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
automountServiceAccountToken: false  # Only enable if app needs Kubernetes API
```

### Role (Namespace-scoped)

For apps that query the Kubernetes API within their namespace:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get"]
    resourceNames: ["app-config"]  # Only this ConfigMap
```

### ClusterRole (Cluster-scoped)

For controllers, operators, or apps that need cluster-wide visibility:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["list", "get"]
```

### RoleBinding (Namespace-scoped)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "mychart.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "mychart.fullname" . }}
    namespace: {{ .Release.Namespace }}
```

### ClusterRoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "mychart.fullname" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "mychart.fullname" . }}
    namespace: {{ .Release.Namespace }}
```

## Network Policies

### Default-deny pattern

Always start restrictive and allow only what's needed:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  podSelector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend  # Only pods with this label can send traffic
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector: {}  # Any pod in the namespace
      ports:
        - protocol: TCP
          port: 53        # DNS
        - protocol: UDP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              name: production
      ports:
        - protocol: TCP
          port: 443       # HTTPS to external services
```

### DNS egress (almost always needed)

```yaml
egress:
  - to:
      - podSelector: {}   # Any pod in the namespace
    ports:
      - protocol: TCP
        port: 53
      - protocol: UDP
        port: 53
  - to:
      - namespaceSelector: {}  # Kube-dns often in different namespace
    ports:
      - protocol: UDP
        port: 53
```

### External egress

For apps that call external APIs:

```yaml
egress:
  - to:
      - podSelector: {}
    ports:
      - protocol: TCP
        port: 443  # HTTPS
  - to:
      - ipBlock:
          cidr: 8.8.8.8/32  # Specific external IP
    ports:
      - protocol: TCP
        port: 443
```

## Common Workload Patterns

### Web Application (Deployment)

- Stateless, can scale horizontally
- Exposes HTTP/HTTPS on a port
- Optional: HPA based on CPU/memory

**Key chart features:**
- Service + Ingress for traffic routing
- HPA for automatic scaling
- Resource requests/limits (important for scaling metrics)
- Liveness/readiness probes on HTTP endpoints

### Background Worker (Deployment with custom restart policy)

- Processes jobs from a queue
- May not expose HTTP
- Health checks via exec or tcp probe

**Key chart features:**
- No Service or Ingress needed
- Health checks via exec (`redis-cli ping`) or tcp
- Consider Pod Disruption Budget if jobs are long-running

### Database (StatefulSet)

- Stateful, requires persistent identity
- Persistent storage
- Headless Service for stable DNS
- Init containers to configure data directories

**Key chart features:**
- StatefulSet with `.spec.serviceName: headless-svc`
- Headless Service (ClusterIP: None)
- PersistentVolumeClaim for data
- Init container to fix ownership: `chown 1000:3000 /data`

### Sidecar pattern

**Example:** App + TLS proxy

```yaml
containers:
  - name: app
    image: myapp:1.0
    ports:
      - name: http
        containerPort: 8080
  - name: envoy-proxy
    image: envoyproxy/envoy:v1.24
    volumeMounts:
      - name: envoy-config
        mountPath: /etc/envoy
volumes:
  - name: envoy-config
    configMap:
      name: {{ include "mychart.fullname" . }}-envoy-config
```

### Init container pattern

**Example:** Database schema initialization

```yaml
initContainers:
  - name: migrate
    image: myapp:1.0
    command: ["./migrate.sh"]
    volumeMounts:
      - name: shared
        mountPath: /app
containers:
  - name: app
    image: myapp:1.0
    volumeMounts:
      - name: shared
        mountPath: /app
volumes:
  - name: shared
    emptyDir: {}
```

### Multi-container with shared volumes

```yaml
containers:
  - name: app
    volumeMounts:
      - name: logs
        mountPath: /var/log/app
  - name: log-shipper
    volumeMounts:
      - name: logs
        mountPath: /var/log/app
        readOnly: true
volumes:
  - name: logs
    emptyDir: {}
```
