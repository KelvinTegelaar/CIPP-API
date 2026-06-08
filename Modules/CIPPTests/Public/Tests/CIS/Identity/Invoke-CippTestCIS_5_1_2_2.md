Allowing standard users to register applications enables a compromised account to plant persistent OAuth backdoors. CIS recommends restricting this to administrators.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateApps = $false }
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
