At Maturity Level 3 the Essential Eight requires phishing-resistant MFA for every user, not just admins. The technical control is a tenant-wide Conditional Access policy that targets *All users* + *All cloud apps* with the built-in **Phishing-resistant MFA** authentication strength.

**Remediation Action**

1. Confirm test E8_MFA_08 is passing (every user has a phishing-resistant method registered).
2. Entra ID > Conditional Access > New policy.
3. Users: All users (exclude break-glass).
4. Cloud apps: All cloud apps.
5. Grant > Require authentication strength > **Phishing-resistant MFA**.
6. Enable the policy.

**Links**
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Conditional Access authentication strengths](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-authentication-strengths)

<!--- Results --->
%TestResult%
