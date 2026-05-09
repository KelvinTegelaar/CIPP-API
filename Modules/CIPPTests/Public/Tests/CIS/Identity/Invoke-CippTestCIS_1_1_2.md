If MFA, Conditional Access, or federation outage locks every administrator out of the tenant, an emergency access (break-glass) account is the only path back in. CIS recommends maintaining at least two such accounts to provide redundancy.

**Remediation Action**

1. Create at least two cloud-only Global Administrator accounts on `<tenant>.onmicrosoft.com`.
2. Use long, randomly generated passwords stored in a physical safe.
3. Exclude these accounts from all Conditional Access policies *except* a CA policy that monitors and alerts on their use.
4. Register strong MFA (FIDO2) for the accounts but plan for MFA-disable scenarios.
5. Use a recognisable naming pattern (e.g. `breakglass1@<tenant>.onmicrosoft.com`).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.1.2](https://www.cisecurity.org/benchmark/microsoft_365)
- [Manage emergency access accounts](https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access)

<!--- Results --->
%TestResult%
