Privileged identities are the highest-value targets in a tenant. ACSC Essential Eight Maturity Level 2 mandates phishing-resistant MFA for them. In Entra ID this is enforced by a Conditional Access policy that targets directory roles with the built-in *Phishing-resistant MFA* authentication strength.

**Remediation Action**

1. Entra ID > Conditional Access > New policy.
2. Users: include Directory roles (all privileged roles such as Global Administrator, Privileged Role Administrator, Security Administrator, etc.).
3. Cloud apps: All cloud apps.
4. Grant > Require authentication strength > **Phishing-resistant MFA**.
5. Enable.

**Links**
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Conditional Access authentication strengths](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-authentication-strengths)

<!--- Results --->
%TestResult%
