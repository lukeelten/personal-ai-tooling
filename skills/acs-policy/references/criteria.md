# ACS SecurityPolicy Criteria Reference

Complete list of all `fieldName` values available in `policySections[].policyGroups[]`.

## Table of Contents
1. [Image Registry & Identity](#image-registry--identity)
2. [Image Contents & Vulnerabilities](#image-contents--vulnerabilities)
3. [Container Configuration](#container-configuration)
4. [Deployment Metadata](#deployment-metadata)
5. [Storage & Volumes](#storage--volumes)
6. [Networking](#networking)
7. [Kubernetes Access & RBAC](#kubernetes-access--rbac)
8. [Process Activity (Runtime)](#process-activity-runtime-only)
9. [Kubernetes Events (Runtime)](#kubernetes-events-runtime-only)
10. [Audit Log Events (Runtime)](#audit-log-events-runtime-only)

---

## Image Registry & Identity

Available in: BUILD, DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Image Registry` | String (RE2 regex) | Registry hostname (e.g., `docker.io`, `quay.io`) |
| `Image Remote` | String (RE2 regex) | Full image path without tag (e.g., `library/nginx`) |
| `Image Tag` | String (RE2 regex) | Image tag (e.g., `latest`, `v1.2.3`) |
| `Image Signature Verified By` | UUID | Signature integration ID from RHACS config |

**Example -- block `latest` tag:**
```yaml
- fieldName: "Image Tag"
  booleanOperator: OR
  values:
    - value: "latest"
```

**Example -- require specific registry (negate = NOT in list):**
```yaml
- fieldName: "Image Registry"
  booleanOperator: OR
  negate: true
  values:
    - value: "registry.redhat.io"
    - value: "quay.io/myorg"
```

---

## Image Contents & Vulnerabilities

Available in: BUILD, DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `CVE` | String (regex) | Specific CVE ID (e.g., `CVE-2021-44228`) |
| `CVSS` | Numeric comparison | CVSS score (e.g., `>=7`, `>=9.0`) |
| `Severity` | Comparison + enum | `UNKNOWN`, `LOW`, `MODERATE`, `IMPORTANT`, `CRITICAL` (e.g., `>=IMPORTANT`) |
| `Fixable` | `true` / `false` | Whether the CVE has a known fix |
| `Fixed By` | String (regex) | Package version that fixes the CVE |
| `Image Component` | `name=version` | Software component (regex, e.g., `log4j=.*`) |
| `Image OS` | String (regex) | Base OS (e.g., `alpine:3.17`, `rhel:8`) |
| `Image Age` | Integer (days) | Minimum days since image was created |
| `Image Scan Age` | Integer (days) | Minimum days since last vulnerability scan |
| `Days Since CVE Was First Discovered In Image` | Integer | Days since CVE first appeared in this image |
| `Days Since CVE Was First Discovered In System` | Integer | Days since CVE first appeared across all images |
| `Image User` | String (regex) | USER directive in Dockerfile |
| `Dockerfile Line` | See below | Matches Dockerfile instructions |
| `Unscanned Image` | `true` / `false` | Image has no scan results |
| `Required Image Label` | `key=value` (regex) | Docker/OCI label that must exist |
| `Disallowed Image Label` | `key=value` (regex) | Docker/OCI label that must NOT exist |

### Dockerfile Line format

The `Dockerfile Line` field uses a special format: the value encodes both the instruction and a regex for the argument.

```yaml
- fieldName: "Dockerfile Line"
  booleanOperator: OR
  values:
    - value: "EXPOSE=22"          # Matches EXPOSE 22
    - value: "USER=root"          # Matches USER root
    - value: "RUN=.*curl.*"       # Matches any RUN with curl
    - value: "ADD=.*"             # Matches any ADD instruction
```

Available instructions: `LABEL`, `RUN`, `CMD`, `EXPOSE`, `ENV`, `ADD`, `COPY`, `ENTRYPOINT`, `VOLUME`, `USER`, `WORKDIR`, `ONBUILD`

---

## Container Configuration

Available in: DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Privileged Container` | `true` / `false` | Container runs in privileged mode |
| `Read-Only Root Filesystem` | `true` / `false` | `readOnlyRootFilesystem` setting. Value `false` means filesystem IS writable (violation) |
| `Allow Privilege Escalation` | `true` / `false` | `allowPrivilegeEscalation` setting |
| `Drop Capabilities` | Capability name | Capabilities that MUST be dropped (AND logic -- all listed must be dropped) |
| `Add Capabilities` | Capability name | Capabilities that must NOT be added (OR logic -- any match = violation) |
| `Seccomp Profile Type` | Enum | `UNCONFINED`, `RUNTIME_DEFAULT`, `LOCALHOST` |
| `AppArmor Profile` | String (regex) | AppArmor profile name |
| `Container Name` | String (regex) | Container name within the pod |
| `Container CPU Request` | Numeric comparison | CPU cores requested (e.g., `<0.1`, `0`) |
| `Container CPU Limit` | Numeric comparison | CPU limit (e.g., `0` for "not set") |
| `Container Memory Request` | Numeric comparison | Memory in MB (e.g., `<64`, `0`) |
| `Container Memory Limit` | Numeric comparison | Memory limit in MB (e.g., `0` for "not set") |
| `Liveness Probe` | `true` / `false` | Has a liveness probe defined. Value `false` = no probe (violation) |
| `Readiness Probe` | `true` / `false` | Has a readiness probe defined |
| `Environment Variable` | See below | Environment variable check |
| `Image User` | String (regex) | Effective user the container runs as |

### Environment Variable format

```yaml
- fieldName: "Environment Variable"
  values:
    - value: "RAW=SECRET_KEY=.*"           # Raw env var with key matching SECRET_KEY
    - value: "SECRET_KEY=password"         # Env sourced from Secret with key "password"
    - value: "CONFIG_MAP_KEY=debug"        # Env sourced from ConfigMap with key "debug"
```

Format: `SOURCE=KEY=VALUE_REGEX` where SOURCE is `RAW`, `SECRET_KEY`, `CONFIG_MAP_KEY`, `FIELD`, or `RESOURCE_FIELD`.

### Drop Capabilities common values

```yaml
- fieldName: "Drop Capabilities"
  booleanOperator: AND          # All must be dropped
  values:
    - value: "ALL"              # Drop all capabilities
```

Or check for specific dangerous capabilities being added:

```yaml
- fieldName: "Add Capabilities"
  booleanOperator: OR           # Any of these = violation
  values:
    - value: "SYS_ADMIN"
    - value: "NET_ADMIN"
    - value: "SYS_PTRACE"
    - value: "NET_RAW"
```

Common Linux capabilities: `ALL`, `SYS_ADMIN`, `NET_ADMIN`, `NET_RAW`, `SYS_PTRACE`, `SYS_MODULE`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `KILL`, `MKNOD`, `AUDIT_WRITE`, `CHOWN`, `SYS_CHROOT`

---

## Deployment Metadata

Available in: DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Namespace` | String (regex) | Deployment namespace |
| `Required Label` | `key=value` (regex) | Label that must exist on the deployment |
| `Required Annotation` | `key=value` (regex) | Annotation that must exist |
| `Disallowed Annotation` | `key=value` (regex) | Annotation not allowed |
| `Runtime Class` | String (regex) | Pod runtimeClassName |
| `Host Network` | `true` / `false` | `hostNetwork` enabled |
| `Host PID` | `true` / `false` | `hostPID` enabled |
| `Host IPC` | `true` / `false` | `hostIPC` enabled |
| `Replicas` | Numeric comparison | Number of replicas (e.g., `<2` for single point of failure) |

---

## Storage & Volumes

Available in: DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Volume Name` | String (regex) | Volume name |
| `Volume Source` | String (regex) | Volume type (e.g., `hostPath`, `emptyDir`, `persistentVolumeClaim`) |
| `Volume Destination` | String (regex) | Mount path inside container (e.g., `/etc`, `/var/run/docker.sock`) |
| `Volume Type` | String (regex) | Volume type classification |
| `Writable Mounted Volume` | `true` / `false` | Volume is mounted read-write |
| `Mount Propagation` | Enum | `NONE`, `HOSTTOCONTAINER`, `BIDIRECTIONAL` |
| `Writable Host Mount` | `true` / `false` | Host path is writable by the container |

**Example -- detect Docker socket mount:**
```yaml
- fieldName: "Volume Destination"
  booleanOperator: OR
  values:
    - value: "/var/run/docker.sock"
    - value: "/var/run/crio/crio.sock"
    - value: "/run/containerd/containerd.sock"
```

---

## Networking

Available in: DEPLOY, RUNTIME (unless noted)

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Exposed Port` | Numeric comparison | Container port (e.g., `22`, `<=1023`) |
| `Exposed Port Protocol` | String (regex) | Protocol (`TCP`, `UDP`) |
| `Exposed Node Port` | Numeric | Port exposed on node |
| `Port Exposure Method` | Enum | `Route`, `LoadBalancer`, `NodePort`, `HostPort`, `Exposure type is not set` |
| `Has Ingress Network Policy` | `true` / `false` | Whether an ingress NetworkPolicy covers this pod |
| `Has Egress Network Policy` | `true` / `false` | Whether an egress NetworkPolicy covers this pod |
| `Unexpected Network Flow Detected` | `true` / `false` | **RUNTIME ONLY** -- Traffic not in baseline |

**Example -- no network policy coverage:**
```yaml
- fieldName: "Has Ingress Network Policy"
  booleanOperator: OR
  values:
    - value: "false"
```

---

## Kubernetes Access & RBAC

Available in: DEPLOY, RUNTIME

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Service Account` | String (regex) | Service account name |
| `Automount Service Account Token` | `true` / `false` | Auto-mounts the SA token |
| `Minimum RBAC Permissions` | Enum | Minimum permission level. Values: `DEFAULT`, `ELEVATED_IN_NAMESPACE`, `ELEVATED_CLUSTER_WIDE`, `CLUSTER_ADMIN` |

**Example -- detect cluster-admin service accounts:**
```yaml
- fieldName: "Minimum RBAC Permissions"
  booleanOperator: OR
  values:
    - value: "CLUSTER_ADMIN"
```

---

## Process Activity (Runtime ONLY)

Only available with `lifecycleStages: [RUNTIME]` and `eventSource: DEPLOYMENT_EVENT`.

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Process Name` | String (regex) | Name of the executed process |
| `Process Ancestor` | String (regex) | Parent process name |
| `Process Arguments` | String (regex) | Command-line arguments |
| `Process UID` | Integer | Unix UID of the process (e.g., `0` for root) |
| `Unexpected Process Executed` | `true` / `false` | Process not in the deployment's baseline |

**Example -- detect shell execution:**
```yaml
- fieldName: "Process Name"
  booleanOperator: OR
  values:
    - value: "bash"
    - value: "sh"
    - value: "dash"
    - value: "zsh"
    - value: "csh"
    - value: "ksh"
```

---

## Kubernetes Events (Runtime ONLY)

Only available with `lifecycleStages: [RUNTIME]` and `eventSource: DEPLOYMENT_EVENT`.

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Kubernetes Resource` | Enum | `PODS_EXEC`, `PODS_PORTFORWARD` |
| `Kubernetes User Name` | String (regex) | User who initiated the action |
| `Kubernetes User Groups` | String (regex) | Group of the user |

**Example -- alert on pod exec:**
```yaml
- fieldName: "Kubernetes Resource"
  booleanOperator: OR
  values:
    - value: "PODS_EXEC"
```

---

## Audit Log Events (Runtime ONLY)

Only available with `lifecycleStages: [RUNTIME]` and `eventSource: AUDIT_LOG_EVENT`.

| fieldName | Value Format | Description |
|-----------|-------------|-------------|
| `Kubernetes Resource` | Enum | `Config maps`, `Secrets`, `ClusterRoles`, `ClusterRoleBindings`, `NetworkPolicies`, `SecurityContextConstraints`, `EgressFirewalls` |
| `Kubernetes API Verb` | Enum | `CREATE`, `DELETE`, `GET`, `PATCH`, `UPDATE` |
| `Kubernetes Resource Name` | String (regex) | Resource name |
| `User Agent` | String (regex) | Client tool (e.g., `kubectl`, `oc`) |
| `Source IP Address` | String (regex) | Source IP (IPv4/IPv6) |
| `Is Impersonated User` | `true` / `false` | Whether the request used impersonation |

**Example -- detect secret access:**
```yaml
policySections:
  - sectionName: "Secrets accessed"
    policyGroups:
      - fieldName: "Kubernetes Resource"
        booleanOperator: OR
        values:
          - value: "Secrets"
      - fieldName: "Kubernetes API Verb"
        booleanOperator: OR
        values:
          - value: "GET"
```

---

## Numeric Comparison Syntax

For numeric fields (`CVSS`, `Exposed Port`, `Container CPU Limit`, etc.), values support comparison operators:

| Syntax | Meaning |
|--------|---------|
| `7` | Exactly 7 |
| `>=7` | Greater than or equal to 7 |
| `>7` | Greater than 7 |
| `<=3` | Less than or equal to 3 |
| `<1024` | Less than 1024 |
| `0` | Not set / zero |

## Severity Comparison Syntax

For the `Severity` field specifically:

| Value | Meaning |
|-------|---------|
| `>=CRITICAL` | Critical only |
| `>=IMPORTANT` | Important and Critical |
| `>=MODERATE` | Moderate, Important, and Critical |
| `>=LOW` | Low and above |

Note: ACS uses `IMPORTANT` (not `HIGH`) for CVE severity in policy criteria values. This differs from the policy's own `severity` field which uses `HIGH_SEVERITY`.

---

## MITRE ATT&CK Mapping (Optional)

```yaml
mitreAttackVectors:
  - tactic: "TA0001"       # Initial Access
    techniques:
      - "T1190"            # Exploit Public-Facing Application
  - tactic: "TA0004"       # Privilege Escalation
    techniques:
      - "T1611"            # Escape to Host
```
