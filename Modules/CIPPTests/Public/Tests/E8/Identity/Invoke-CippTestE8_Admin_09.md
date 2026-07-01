PIM activation should require MFA and a typed justification for every privileged role activation. This raises the bar against stolen tokens and provides an audit trail.

**Remediation Action**

1. Entra ID > PIM > Microsoft Entra roles > Roles.
2. For each role, open *Role settings* > *Edit*.
3. On Activation, tick **Azure MFA** and **Require justification on activation**.

**Links**
- [Configure Microsoft Entra role settings in PIM](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings)

<!--- Results --->
%TestResult%
