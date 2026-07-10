Essential Eight Maturity Level 2 requires phishing-resistant MFA for privileged users. Before users can be required to use it, the tenant must have at least one phishing-resistant method (FIDO2 security keys, Windows Hello for Business, or certificate-based authentication) enabled in the Authentication methods policy.

**Remediation Action**

1. Entra ID > Authentication methods > Policies.
2. Enable at least one of: FIDO2 security key, Windows Hello for Business, Certificate-based authentication.
3. Target the appropriate user/group scope and save.

**Links**
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Authentication methods policy](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-authentication-methods-manage)

<!--- Results --->
%TestResult%
