OAuth phishing tricks users into consenting to malicious applications, granting attackers persistent Graph access without ever stealing a password. Disabling user consent eliminates this attack class.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ PermissionGrantPoliciesAssigned = @() }
```

(Or assign `ManagePermissionGrantsForSelf.microsoft-user-default-low` if low-risk consent is acceptable.)

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.5.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
