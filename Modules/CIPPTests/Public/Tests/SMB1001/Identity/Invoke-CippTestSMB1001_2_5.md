SMB1001 (2.5) — Level 2+ — multi-factor authentication or two-step verification on all employee email accounts, including administrators. The test passes if MFA is enforced through any of: Security Defaults, an enforced Conditional Access policy targeting Office 365 / all apps, or per-user MFA on every active member account.

**Remediation Action**

Choose one path:

- Enable **Security Defaults** in Microsoft Entra (Identity > Overview > Properties > Manage Security defaults).
- Deploy a **Conditional Access policy** that requires MFA for all users targeting all cloud apps (or Office 365). With CIPP: `standards.ConditionalAccessTemplate`.
- Enforce **per-user MFA** on every member account (legacy). With CIPP: `standards.PerUserMFA`.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Common Conditional Access policy: Require MFA for all users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa)

<!--- Results --->
%TestResult%
