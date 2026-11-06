Trial Teams tenants are short-lived, low-friction accounts attackers spin up to bypass identity controls. Block federation with them.

**Remediation Action**

Teams admin centre > Users > External access: uncheck "People in my organization can communicate with accounts in trial Teams tenants".

```powershell
Set-CsTenantFederationConfiguration -ExternalAccessWithTrialTenants Blocked
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 8.2.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
