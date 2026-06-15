Security groups grant access to resources. Allowing standard users to create security groups bypasses access governance and is a common privilege escalation path — a compromised user can create deceptively named groups that an administrator later trusts with elevated access or excludes from Conditional Access.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateSecurityGroups = $false }
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.3.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
