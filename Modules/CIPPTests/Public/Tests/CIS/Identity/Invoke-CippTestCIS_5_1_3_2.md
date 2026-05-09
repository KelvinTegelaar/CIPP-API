Security groups grant access to resources. Allowing standard users to create security groups bypasses access governance and is a common privilege escalation path.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateSecurityGroups = $false }
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.3.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
