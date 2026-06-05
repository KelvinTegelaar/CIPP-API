Standard users can create new Microsoft Entra tenants by default and inherit Global Administrator inside that new tenant. This bypasses governance, allows shadow IT, and may pose a data exfiltration risk.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateTenants = $false }
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.2.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
