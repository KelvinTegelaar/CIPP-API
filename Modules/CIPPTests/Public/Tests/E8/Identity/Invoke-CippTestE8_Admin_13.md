High-privilege OAuth grants (e.g. application permissions on Microsoft Graph such as `Directory.ReadWrite.All`, `RoleManagement.ReadWrite.Directory`, `Application.ReadWrite.All`, `Mail.ReadWrite`) effectively grant Global-Admin-equivalent access via a service principal. Review these regularly.

**Remediation Action**

1. Entra ID > Enterprise applications > All applications.
2. For each app with admin-consented permissions, review *Permissions* and revoke unused.
3. Use Microsoft Defender for Cloud Apps / Microsoft 365 Defender to alert on new high-privilege consents.

**Links**
- [Investigate risky OAuth apps](https://learn.microsoft.com/en-us/defender-cloud-apps/investigate-risky-oauth)

<!--- Results --->
%TestResult%
