A tenant-wide Conditional Access policy that requires MFA on every sign-in to every cloud app is the baseline control for Essential Eight ML1. Without it, MFA remains optional and attackers can bypass it via legacy clients or unprotected applications.

**Remediation Action**

1. Entra ID > Conditional Access > New policy.
2. Users: All users (exclude break-glass).
3. Cloud apps: All cloud apps.
4. Grant: Require multifactor authentication (or an Authentication Strength).
5. Enable policy.

**Links**
- [ACSC Essential Eight - Multifactor Authentication](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Common CA policy: Require MFA for all users](https://learn.microsoft.com/en-us/azure/active-directory/conditional-access/howto-conditional-access-policy-all-users-mfa)

<!--- Results --->
%TestResult%
