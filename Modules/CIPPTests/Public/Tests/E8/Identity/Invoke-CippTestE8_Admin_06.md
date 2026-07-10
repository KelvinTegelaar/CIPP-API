ISM-1509 — privileged access events are centrally logged. The Entra ID Sign-in log and Audit log must be forwarded to a SIEM and retained for 12 months. This is configured under *Entra ID > Diagnostic settings* and depends on a target Log Analytics workspace / event hub / storage account that lives outside the tenant CIPP can read; verify manually.

**Remediation Action**

1. Entra ID > Diagnostic settings > Add diagnostic setting.
2. Send `SignInLogs`, `AuditLogs`, `RiskyUsers`, `UserRiskEvents`, `ServicePrincipalSignInLogs` to a Log Analytics workspace / Sentinel / Event Hub.
3. Confirm retention ≥ 12 months on the destination.

**Links**
- [Entra ID diagnostic settings](https://learn.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-integrate-activity-logs-with-azure-monitor-logs)
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)

<!--- Results --->
%TestResult%
