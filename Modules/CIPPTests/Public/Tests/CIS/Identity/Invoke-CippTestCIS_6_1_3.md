`AuditBypassEnabled` is intended for service accounts that would otherwise generate audit noise. It is also a powerful evasion control if applied to a regular mailbox — actions taken on a bypassed mailbox are not audited.

**Remediation Action**

```powershell
Get-MailboxAuditBypassAssociation | Where-Object AuditBypassEnabled | Set-MailboxAuditBypassAssociation -AuditBypassEnabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.1.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
