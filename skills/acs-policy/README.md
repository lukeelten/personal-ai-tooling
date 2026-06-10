# acs-policy

Generate Red Hat Advanced Cluster Security (RHACS / StackRox) `SecurityPolicy` Custom Resources as YAML — ready to apply to your cluster or commit to a GitOps repo.

---

## What it does

Produces valid `config.stackrox.io/v1alpha1` SecurityPolicy CRs that can be applied with `kubectl`/`oc` or synced via ArgoCD. The skill handles the full structure: lifecycle stages, enforcement actions, scopes, exclusions, and the `policySections` detection logic.

---

## How to trigger it

Describe the security concern you want to enforce. You don't need to know the CR structure — just explain the intent:

```
Block privileged containers in production namespaces
Prevent images from untrusted registries at deploy time
Alert when a crypto miner process runs in any pod
Fail the build if an image has critical fixable CVEs
```

You also don't need to say "ACS" or "SecurityPolicy" — the skill activates whenever the request maps to a container security policy, admission control rule, or runtime enforcement concern.

---

## Lifecycle stages

| Stage | When it runs | Typical use |
|---|---|---|
| `BUILD` | CI/CD image scanning | CVE checks, Dockerfile rules |
| `DEPLOY` | Admission controller at deploy time | Privilege, capabilities, host namespaces |
| `RUNTIME` | Running workloads | Process execution, network flows |

A policy can span multiple stages — e.g. block critical CVEs at both `BUILD` and `DEPLOY`.

---

## Enforcement actions

| Action | Stage | Effect |
|---|---|---|
| *(empty)* | Any | Inform only — creates an alert |
| `FAIL_BUILD_ENFORCEMENT` | BUILD | Fails the CI/CD pipeline |
| `FAIL_DEPLOYMENT_CREATE_ENFORCEMENT` | DEPLOY | Blocks new deployments |
| `FAIL_DEPLOYMENT_UPDATE_ENFORCEMENT` | DEPLOY | Blocks deployment updates |
| `KILL_POD_ENFORCEMENT` | RUNTIME | Kills violating pods |
| `FAIL_KUBE_REQUEST_ENFORCEMENT` | RUNTIME | Blocks exec / port-forward |

**Recommended rollout**: start with inform-only for 2–4 weeks, review alerts for false positives, add exclusions, then enable enforcement.

---

## Quick examples

<details>
<summary>Block privileged containers</summary>

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: no-privileged-containers
  namespace: stackrox
spec:
  policyName: "No Privileged Containers in Production"
  severity: CRITICAL_SEVERITY
  lifecycleStages: [DEPLOY]
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
  policySections:
    - sectionName: "Privileged mode check"
      policyGroups:
        - fieldName: "Privileged Container"
          booleanOperator: OR
          values:
            - value: "true"
```
</details>

<details>
<summary>Require images from trusted registries</summary>

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: trusted-registries-only
  namespace: stackrox
spec:
  policyName: "Images Must Come From Trusted Registries"
  severity: HIGH_SEVERITY
  lifecycleStages: [BUILD, DEPLOY]
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_BUILD_ENFORCEMENT
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
  policySections:
    - sectionName: "Registry allowlist"
      policyGroups:
        - fieldName: "Image Registry"
          booleanOperator: OR
          negate: true
          values:
            - value: "registry.redhat.io"
            - value: "quay.io/myorg"
```
</details>

<details>
<summary>Block critical fixable CVEs</summary>

```yaml
apiVersion: config.stackrox.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: block-critical-fixable-cves
  namespace: stackrox
spec:
  policyName: "Block Critical Fixable CVEs"
  severity: CRITICAL_SEVERITY
  lifecycleStages: [BUILD, DEPLOY]
  eventSource: NOT_APPLICABLE
  enforcementActions:
    - FAIL_BUILD_ENFORCEMENT
    - FAIL_DEPLOYMENT_CREATE_ENFORCEMENT
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
</details>

---

## Applying a policy

```bash
# Apply to the namespace where RHACS Central is installed (typically 'stackrox')
oc apply -f my-policy.yaml -n stackrox

# Verify it appears in the RHACS UI
# Platform Configuration → Policy Management
```

For GitOps workflows, commit the YAML to your repo and sync via ArgoCD. The CR is the source of truth — any changes made in the RHACS UI will be reconciled back to the declared state.

---

## Severity guide

| Severity | Meaning |
|---|---|
| `CRITICAL_SEVERITY` | Immediately exploitable — host compromise, active attack surface |
| `HIGH_SEVERITY` | Significant misconfiguration requiring another step to exploit |
| `MEDIUM_SEVERITY` | Missing hardening measure that weakens the security posture |
| `LOW_SEVERITY` | Hygiene / best-practice violation |

---

## File structure

```
acs-policy/
├── SKILL.md                  # Agent-facing instructions (loaded by OpenCode)
├── README.md                 # This file
└── references/
    └── criteria.md           # Full list of available fieldName values and their inputs
```

The `references/criteria.md` file is the authoritative reference for every `fieldName` value accepted by `policySections` — consult it when you need a criterion that isn't covered by the examples above.
