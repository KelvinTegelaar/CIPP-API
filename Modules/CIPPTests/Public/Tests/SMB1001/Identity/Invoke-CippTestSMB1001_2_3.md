SMB1001 (2.3) — Level 2+ — every employee must have their own username and password; shared logins are not permitted. In Microsoft 365 the most common shared-credential risk is a shared mailbox where the underlying Entra account remains enabled and could be signed into directly. Microsoft's recommendation is to disable sign-in on all shared, scheduling, room, and equipment mailboxes so employees access them only via delegated permissions.

**Remediation Action**

```powershell
# Disable sign-in for shared mailbox accounts
Get-Mailbox -RecipientTypeDetails SharedMailbox,SchedulingMailbox,RoomMailbox,EquipmentMailbox |
    ForEach-Object { Update-MgUser -UserId $_.ExternalDirectoryObjectId -AccountEnabled:$false }
```

Or use the CIPP standards `standards.DisableSharedMailbox` and `standards.DisableResourceMailbox`.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Block sign-in for shared mailbox accounts](https://learn.microsoft.com/en-us/microsoft-365/admin/email/about-shared-mailboxes#block-sign-in-for-the-shared-mailbox-account)

<!--- Results --->
%TestResult%
