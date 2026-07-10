ISM-1547 — backups must be performed regularly, retained for an organisation-determined period, stored separately from the source data, and **tested**. Microsoft retention is not a backup. Use Microsoft 365 Backup or a third-party solution (Veeam, Datto, Druva, AvePoint, etc.) and run a documented restore test at least quarterly.

**Remediation Action**

1. Provision a Microsoft 365 backup solution covering Exchange, OneDrive, SharePoint, and Teams.
2. Schedule a quarterly test restore and record the results in your backup runbook.
3. Verify the backup admin account is not synced from on-premises and uses an isolated identity.

**Links**
- [Microsoft 365 Backup](https://learn.microsoft.com/en-us/microsoft-365/backup/)
- [ACSC Essential Eight - Regular Backups](https://learn.microsoft.com/en-us/compliance/anz/e8-backup)

<!--- Results --->
%TestResult%
