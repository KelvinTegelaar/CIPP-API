Insurers ask whether the accounts that manage backups are separate from production and admin accounts, so an attacker with a tenant admin account cannot also delete backups. When a backup portal signs in through Entra ID, this check lists who is assigned to it and which of those users hold a directory role. The answer itself comes from the MSP.

**Remediation Action**

1. Use dedicated accounts for the backup portal that hold no directory role in the tenant.
2. Remove tenant administrators from the backup app's user assignments.

<!--- Results --->
%TestResult%
