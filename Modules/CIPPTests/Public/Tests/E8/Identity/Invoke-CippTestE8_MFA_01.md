All staff (and any service accounts that interact with the tenant) must be registered for multifactor authentication. The Essential Eight requires MFA at Maturity Level 1 across all users so a stolen password cannot, on its own, grant access to corporate data.

**Remediation Action**

1. Identify users without MFA registration (this test lists them).
2. Enable a Conditional Access policy or Security Defaults to force registration on next sign-in.
3. Validate via Entra ID > Authentication methods > User registration details that `isMfaCapable = true`.

**Links**
- [ACSC Essential Eight - Multifactor Authentication](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)
- [Plan an Authentication methods deployment](https://learn.microsoft.com/en-us/azure/active-directory/authentication/howto-authentication-methods-activity)

<!--- Results --->
%TestResult%
