Without the unified audit log enabled, the tenant has no forensic record of admin or user activity. Every IR investigation depends on this.

**Remediation Action**

```powershell
Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 3.1.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
