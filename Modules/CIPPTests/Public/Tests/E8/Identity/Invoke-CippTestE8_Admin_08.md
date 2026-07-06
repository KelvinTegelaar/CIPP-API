ISM-1508 — privileged accounts are time-bound and reauthenticated for each session. Microsoft's equivalent is Privileged Identity Management (PIM): admins are *eligible* for a role and must activate it for a limited time. This test fails when highly-privileged roles have permanent (active) assignments rather than eligible-only.

**Remediation Action**

1. Entra ID > Privileged Identity Management > Microsoft Entra roles.
2. For each role listed, convert all members from *Active* to *Eligible*.
3. Set max activation duration ≤ 8 hours; require justification + MFA on activation.

**Links**
- [PIM in Microsoft Entra](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-configure)
- [ACSC Essential Eight - Restrict Administrative Privileges](https://learn.microsoft.com/en-us/compliance/anz/e8-admin)

<!--- Results --->
%TestResult%
