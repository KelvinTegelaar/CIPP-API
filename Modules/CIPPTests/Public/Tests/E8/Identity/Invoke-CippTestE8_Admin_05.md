ISM-1648 — privileged access disabled after 45 days of inactivity. Stale privileged accounts are a common foothold for attackers; if no one is signing in, the account either should not exist or should be disabled. The control window is signal-of-life via Entra ID `signInActivity.lastSignInDateTime`.

**Remediation Action**

1. Review each stale privileged account listed.
2. Disable, delete, or remove privileged role assignments where appropriate.
3. Where the account is genuinely needed for monthly tasks, document the exception and consider PIM eligible assignment instead of permanent.

**Links**
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)
- [ISM-1648](https://www.cyber.gov.au/ism)

<!--- Results --->
%TestResult%
