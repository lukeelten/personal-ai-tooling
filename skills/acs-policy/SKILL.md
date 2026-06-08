---
name: acs-policy
description: "Generate Red Hat Advanced Cluster Security (ACS/RHACS) SecurityPolicy Custom Resources as YAML. Use this skill whenever the user wants to create, write, or modify ACS security policies, StackRox policies, RHACS policy-as-code CRs, or asks about container security policies for OpenShift/Kubernetes clusters that should be enforced via ACS. Also use when the user mentions blocking images with CVEs, preventing privileged containers, enforcing runtime security, or writing admission control policies for ACS -- even if they don't explicitly say 'ACS' but describe something that clearly maps to an ACS policy."
---

# Writing ACS SecurityPolicy Custom Resources

This skill generates Red Hat Advanced Cluster Security (ACS/RHACS) SecurityPolicy Custom Resources in YAML format, following the `config.stackrox.io/v1alpha1` API. These CRs enable policy-as-code workflows where security policies are managed via GitOps and applied with `kubectl` or `oc`.

## When the user asks for a policy

1. Identify what security concern they want to address
2. Determine the appropriate lifecycle stage(s) (BUILD, DEPLOY, RUNTIME)
3. Select the right policy criteria fields
4. Recommend severity and enforcement based on the context
5. Output valid YAML that can be applied directly to the cluster

## CR Structure

Every ACS SecurityPolicy CR follows this structure:

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: short-dns-name            # Kubernetes-valid name
  namespace: stackrox             # Must match Central's namespace
spec:
  policyName: "Human-Readable Name"
  description: "What this policy detects"
  rationale: "Why this matters from a security perspective"
  remediation: "Steps to fix violations"
  disabled: false
  severity: HIGH_SEVERITY         # LOW | MEDIUM | HIGH | CRITICAL
  categories:
    - "Security Best Practices"
  lifecycleStages:
    - DEPLOY
  eventSource: NOT_APPLICABLE     # NOT_APPLICABLE | DEPLOYMENT_EVENT | AUDIT_LOG_EVENT
  enforcementActions: []          # Empty = inform only
  scope: []                       # Empty = applies everywhere
  exclusions: []
  policySections:
    - sectionName: "Rule description"
      policyGroups:
        - fieldName: "Privileged Container"
          booleanOperator: OR
          values:
            - value: "true"
```

## Key Fields Explained

### severity
Reflects the risk level of what the policy detects:
- `CRITICAL_SEVERITY` -- Immediate exploitable risk (host compromise, active attacks, known RCE)
- `HIGH_SEVERITY` -- Significant misconfiguration or vulnerability (root containers, host namespaces, fixable critical CVEs)
- `MEDIUM_SEVERITY` -- Weakened posture (no read-only rootfs, latest tag, missing probes)
- `LOW_SEVERITY` -- Hygiene issues (missing labels, old images, no resource requests)

### lifecycleStages
Determines when the policy is evaluated:
- `BUILD` -- During CI/CD image scanning. Only image-related criteria (CVEs, Dockerfile, registry).
- `DEPLOY` -- At deployment creation/update. Includes all BUILD criteria plus container config, volumes, networking.
- `RUNTIME` -- On running workloads. Includes everything plus process activity and network flows.

Use multiple stages when the same criteria applies at different points (e.g., CVE checks at both BUILD and DEPLOY).

### eventSource
Required when `RUNTIME` is in lifecycleStages:
- `DEPLOYMENT_EVENT` -- Process executions, network activity, pod exec/port-forward
- `AUDIT_LOG_EVENT` -- Kubernetes audit log records (API access patterns)

Set to `NOT_APPLICABLE` when RUNTIME is not used.

### enforcementActions
What happens when a violation is detected:

| Action | Stage | Effect |
|--------|-------|--------|
| (empty list) | Any | Inform only -- creates alert |
| `FAIL_BUILD_ENFORCEMENT` | BUILD | Fails CI/CD pipeline |
| `FAIL_DEPLOYMENT_CREATE_ENFORCEMENT` | DEPLOY | Blocks deployment via admission controller |
| `FAIL_DEPLOYMENT_UPDATE_ENFORCEMENT` | DEPLOY | Blocks deployment updates |
| `SCALE_TO_ZERO_ENFORCEMENT` | DEPLOY | Scales replicas to 0 (soft) |
| `UNSATISFIABLE_NODE_CONSTRAINT_ENFORCEMENT` | DEPLOY | Adds impossible scheduling constraint (soft) |
| `KILL_POD_ENFORCEMENT` | RUNTIME | Kills violating pods |
| `FAIL_KUBE_REQUEST_ENFORCEMENT` | RUNTIME | Blocks exec/port-forward |

Start with inform-only in production, then move to enforcement after reviewing violations and adding necessary exclusions.

### scope
Restricts where the policy applies. If empty, applies everywhere.

```yaml
scope:
  - cluster: "production"
    namespace: "frontend"        # Supports RE2 regex
    label:
      key: "app"
      value: "web"
```

### exclusions
Exempts specific workloads from the policy:

```yaml
exclusions:
  - name: "System monitoring"
    deployment:
      name: "prometheus"
      scope:
        namespace: "monitoring"
  - name: "Temporary exception"
    deployment:
      scope:
        namespace: "legacy-app"
    expiration: "2025-06-30T00:00:00Z"
```

The namespaces `stackrox`, `kube-system`, and `istio-system` are excluded from enforcement by default.

### policySections
The rules that define what triggers the policy. This is where the actual detection logic lives.

**Logic:**
- Values within a `policyGroup` are combined with `booleanOperator` (OR or AND)
- Groups within a `policySection` are ANDed together
- Multiple `policySections` are ORed together (any section matching = violation)

```yaml
policySections:
  - sectionName: "Critical CVEs that are fixable"
    policyGroups:
      - fieldName: "Severity"
        booleanOperator: OR
        values:
          - value: ">=CRITICAL"
      - fieldName: "Fixable"    # ANDed with Severity above
        booleanOperator: OR
        values:
          - value: "true"
```

Use `negate: true` on a group to invert the match (e.g., "registry is NOT in allowed list").

For the full list of available `fieldName` values and their allowed inputs, read `references/criteria.md`.

## Best Practices for Policy Design

### Enforcement rollout
Deploy policies in phases:
1. Start with `enforcementActions: []` (inform only) for 2-4 weeks
2. Review violation alerts to find false positives
3. Add exclusions for legitimate cases
4. Enable enforcement once confidence is high

### Severity alignment
Match severity to real-world impact:
- Does this enable full host compromise? -> CRITICAL
- Does this weaken isolation but require another vulnerability to exploit? -> HIGH
- Is this a missing hardening measure? -> MEDIUM
- Is this a hygiene/best-practice violation? -> LOW

### Scoping strategy
- Production clusters: strictest enforcement
- Staging: enforce with fewer exceptions (catch issues before prod)
- Development: inform-only for most policies (don't block developer velocity)
- System namespaces (kube-system, openshift-*): exclude unless you have specific system-level policies

### Categories
Use standard categories to organize policies in the RHACS dashboard:
- `Vulnerability Management` -- CVE-related policies
- `Security Best Practices` -- Container hardening (privileges, capabilities, filesystem)
- `DevOps Best Practices` -- Image hygiene (tags, age, resource limits)
- `Network` -- Network policy coverage, port exposure
- `Supply Chain Security` -- Registry restrictions, image signing
- `Anomalous Activity` -- Runtime behavioral detection
- `Kubernetes` -- RBAC, service accounts, secrets handling
- `Privileges` -- Privilege escalation, capabilities, host access

### Kubernetes Pod Security Standards mapping
If implementing PSS Baseline or Restricted profiles via ACS:

**Baseline** (prevent known privilege escalations):
- No privileged containers
- No hostNetwork/hostPID/hostIPC
- No dangerous capabilities (SYS_ADMIN, NET_RAW if stricter)
- No hostPath volumes

**Restricted** (full hardening):
- All of Baseline, plus:
- Must run as non-root
- All capabilities dropped
- allowPrivilegeEscalation: false
- Seccomp profile required (RuntimeDefault or Localhost)
- Read-only root filesystem

## Complete Examples

### Block privileged containers in production

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: no-privileged-containers
  namespace: stackrox
spec:
  policyName: "No Privileged Containers in Production"
  description: "Prevents containers from running in privileged mode, which grants full host access"
  rationale: "Privileged containers have unrestricted access to the host kernel and all devices, making container escape trivial"
  remediation: "Remove securityContext.privileged or set it to false. If host access is genuinely needed, use specific capabilities instead."
  disabled: false
  severity: CRITICAL_SEVERITY
  categories:
    - "Security Best Practices"
    - "Privileges"
  lifecycleStages:
    - DEPLOY
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
  scope:
    - label:
        key: "environment"
        value: "production"
  exclusions:
    - name: "System components"
      deployment:
        scope:
          namespace: "kube-system"
  policySections:
    - sectionName: "Privileged mode check"
      policyGroups:
        - fieldName: "Privileged Container"
          booleanOperator: OR
          values:
            - value: "true"
```

### Require images from trusted registries

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: trusted-registries-only
  namespace: stackrox
spec:
  policyName: "Images Must Come From Trusted Registries"
  description: "Only allows images pulled from approved container registries"
  rationale: "Untrusted registries may host images with backdoors, malware, or unpatched vulnerabilities"
  remediation: "Rebuild the image using a base from an approved registry (registry.redhat.io, quay.io/your-org, or your internal registry)"
  disabled: false
  severity: HIGH_SEVERITY
  categories:
    - "Supply Chain Security"
  lifecycleStages:
    - BUILD
    - DEPLOY
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_BUILD_ENFORCEMENT
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
  scope: []
  exclusions:
    - name: "System namespaces"
      deployment:
        scope:
          namespace: "^(kube-system|openshift-.*|stackrox)$"
  policySections:
    - sectionName: "Registry allowlist"
      policyGroups:
        - fieldName: "Image Registry"
          booleanOperator: OR
          negate: true
          values:
            - value: "registry.redhat.io"
            - value: "quay.io/myorg"
            - value: "internal-registry.example.com"
```

### Detect crypto mining at runtime

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: detect-crypto-mining
  namespace: stackrox
spec:
  policyName: "Cryptocurrency Mining Process Detected"
  description: "Detects execution of known cryptocurrency mining binaries"
  rationale: "Crypto miners indicate a compromised workload -- an attacker is using your compute resources"
  remediation: "Investigate the container for compromise. Check how the miner was deployed (supply chain attack, runtime exploit, or insider threat)."
  disabled: false
  severity: CRITICAL_SEVERITY
  categories:
    - "Anomalous Activity"
  lifecycleStages:
    - RUNTIME
  eventSource: DEPLOYMENT_EVENT
  enforcementActions:
    - KILL_POD_ENFORCEMENT
  scope: []
  exclusions: []
  policySections:
    - sectionName: "Known mining processes"
      policyGroups:
        - fieldName: "Process Name"
          booleanOperator: OR
          values:
            - value: "xmrig"
            - value: "minerd"
            - value: "cpuminer"
            - value: "cgminer"
            - value: "bfgminer"
            - value: "ethminer"
            - value: "nbminer"
```

### Block critical fixable CVEs

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: block-critical-fixable-cves
  namespace: stackrox
spec:
  policyName: "Block Critical Fixable CVEs"
  description: "Prevents deployment of images containing critical-severity vulnerabilities that have a known fix"
  rationale: "If a fix exists, there is no reason to deploy with a critical vulnerability"
  remediation: "Update the affected package to the fixed version. Run the scanner locally to verify the fix."
  disabled: false
  severity: CRITICAL_SEVERITY
  categories:
    - "Vulnerability Management"
  lifecycleStages:
    - BUILD
    - DEPLOY
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_BUILD_ENFORCEMENT
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
  scope: []
  exclusions: []
  policySections:
    - sectionName: "Critical fixable vulnerabilities"
      policyGroups:
        - fieldName: "Severity"
          booleanOperator: OR
          values:
            - value: ">=CRITICAL"
        - fieldName: "Fixable"
          booleanOperator: OR
          values:
            - value: "true"
```

## Applying Policies

```bash
# Apply to the cluster where RHACS Central runs
oc apply -f my-policy.yaml -n stackrox

# Verify it appears in RHACS
# Check the RHACS portal under Platform Configuration > Policy Management

# For GitOps workflows, commit to a repo and sync via ArgoCD
```

The CR must be applied to the namespace where Central is installed (typically `stackrox`). The `spec.policyName` must be unique across all policies in the RHACS instance.

## Policy drift

If someone modifies the policy through the RHACS UI, the CR will be reconciled back to its declared state within 10 hours (or on the next reconciliation cycle). The CR is the source of truth -- treat the RHACS UI as read-only for policy-as-code managed policies.
