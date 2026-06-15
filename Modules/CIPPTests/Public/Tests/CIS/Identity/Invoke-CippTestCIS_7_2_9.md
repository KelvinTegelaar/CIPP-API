Set guest external access to expire after a fixed window so dormant guests automatically lose access without manual cleanup.

**Remediation Action**

```powershell
Set-SPOTenant -ExternalUserExpirationRequired $true -ExternalUserExpireInDays 30
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 7.2.9](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
