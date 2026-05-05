SMB1001 (3.1) — Level 1+ — implement a backup and recovery strategy for important digital data, with at least one offline copy isolated from the business network and a six-month minimum recovery history. Microsoft 365 native data-preservation features (Litigation Hold, retention policies, archive mailboxes) cover part of the recovery surface but do not satisfy the offline-isolated backup requirement on their own — that needs a third-party M365 backup product (Veeam, Datto, Spanning, AvePoint, or Microsoft 365 Backup).

This test verifies the M365-native preservation half. Evidence the offline-backup half to your Dynamic Standard Certifier separately.

**Remediation Action**

```powershell
# Enable Litigation Hold on all user mailboxes
Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited |
    Set-Mailbox -LitigationHoldEnabled $true
```

Or use CIPP `standards.EnableLitigationHold`. Pair with a third-party M365 backup product for offline copies.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Litigation Hold in Exchange Online](https://learn.microsoft.com/en-us/purview/ediscovery-create-a-litigation-hold)

<!--- Results --->
%TestResult%
