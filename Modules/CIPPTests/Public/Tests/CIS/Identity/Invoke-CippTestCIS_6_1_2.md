Per-mailbox audit actions (AuditOwner / AuditDelegate / AuditAdmin) determine which mailbox events are written to the audit log. Without explicit actions, key forensic events (MailItemsAccessed, SoftDelete, etc.) may not be recorded.

**Remediation Action**

```powershell
Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited | Set-Mailbox -AuditEnabled $true -AuditOwner @{Add='MailboxLogin','HardDelete','MoveToDeletedItems','SoftDelete','UpdateFolderPermissions','UpdateInboxRules','MailItemsAccessed'}
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.1.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
