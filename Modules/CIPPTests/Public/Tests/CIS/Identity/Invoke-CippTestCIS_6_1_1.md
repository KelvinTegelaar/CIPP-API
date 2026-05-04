If `AuditDisabled` is true at the organisation level, no mailbox actions are recorded — even with the Unified Audit Log on.

**Remediation Action**

```powershell
Set-OrganizationConfig -AuditDisabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.1.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
