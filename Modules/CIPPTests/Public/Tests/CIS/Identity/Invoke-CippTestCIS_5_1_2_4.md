The Entra admin centre exposes directory contents (users, groups, configuration) to anyone signed in. Standard users do not need access and should be blocked from the portal.

**Remediation Action**

```powershell
Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/beta/admin/entra/uxSetting' -Body '{ "restrictNonAdminAccess": true }'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.2.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
