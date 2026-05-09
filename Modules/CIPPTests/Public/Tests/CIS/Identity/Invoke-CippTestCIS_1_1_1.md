Microsoft 365 administrators should authenticate using cloud-only identities. Synchronized on-premises accounts inherit the security posture of the on-premises Active Directory; if the directory is compromised, every privileged identity is compromised with it. Privileged accounts should also avoid productivity licenses to reduce the attack surface (mail, Teams, browsing) on highly-targeted identities.

**Remediation Action**

1. Create a dedicated cloud-only account on the `<tenant>.onmicrosoft.com` domain for each administrator.
2. Remove `onPremisesSyncEnabled` accounts from privileged role assignments.
3. Strip productivity licenses from administrative accounts (Entra ID P2 only is sufficient for most cases).

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.1.1](https://www.cisecurity.org/benchmark/microsoft_365)
- [Protect M365 admin accounts](https://learn.microsoft.com/en-us/microsoft-365/admin/add-users/protect-global-admins)

<!--- Results --->
%TestResult%
