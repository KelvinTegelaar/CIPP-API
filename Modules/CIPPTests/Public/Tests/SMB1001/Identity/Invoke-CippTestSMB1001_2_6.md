SMB1001 (2.6) — Level 3+ — multi-factor authentication for all user and administrator accounts on all cloud-hosted business applications, including social media. The strongest Microsoft 365 implementation is a Conditional Access policy that targets All Cloud Apps with the grant control "Require multi-factor authentication" applied to All Users.

**Remediation Action**

Deploy a Conditional Access policy:

- **Users**: All users
- **Cloud apps**: All cloud apps
- **Grant**: Require multi-factor authentication

Use CIPP `standards.ConditionalAccessTemplate` with the "Require MFA for all users" template.

For tenants without Entra ID Premium, fall back to Security Defaults or per-user MFA on every active member account.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Common Conditional Access policy: Require MFA for all users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa)

<!--- Results --->
%TestResult%
