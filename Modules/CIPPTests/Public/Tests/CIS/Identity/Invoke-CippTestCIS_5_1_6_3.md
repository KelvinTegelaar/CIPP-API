Limiting guest invitations to administrators and a dedicated Guest Inviter role provides oversight and a clear audit trail for who is bringing externals into the tenant.

**Remediation Action**

```powershell
Update-MgPolicyAuthorizationPolicy -AllowInvitesFrom 'adminsAndGuestInviters'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.6.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
