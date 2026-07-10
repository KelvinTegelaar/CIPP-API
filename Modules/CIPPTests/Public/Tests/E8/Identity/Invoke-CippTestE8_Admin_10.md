For tier-zero roles (Global Administrator, Privileged Role Administrator) activation should require approval from a second administrator. This adds a four-eyes control on the most damaging roles.

**Remediation Action**

1. Entra ID > PIM > Microsoft Entra roles > Roles > *Global Administrator* > Role settings > Edit.
2. On Activation, enable **Require approval to activate** and add at least one approver.
3. Repeat for *Privileged Role Administrator*.

**Links**
- [Approve activation requests in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-approval-workflow)

<!--- Results --->
%TestResult%
