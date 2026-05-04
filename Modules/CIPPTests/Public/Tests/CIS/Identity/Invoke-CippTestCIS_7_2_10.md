Email-based verification codes for guest sign-ins should re-prompt regularly so a stale link / forwarded code can't be used indefinitely.

**Remediation Action**

```powershell
Set-SPOTenant -EmailAttestationRequired $true -EmailAttestationReAuthDays 15
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 7.2.10](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
