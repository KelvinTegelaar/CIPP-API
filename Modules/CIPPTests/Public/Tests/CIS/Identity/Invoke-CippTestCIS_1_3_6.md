Customer Lockbox requires explicit organisational approval before Microsoft engineers can access tenant data during a support engagement. Without it, an engineer can access content silently.

**Remediation Action**

```powershell
Set-OrganizationConfig -CustomerLockBoxEnabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.3.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
