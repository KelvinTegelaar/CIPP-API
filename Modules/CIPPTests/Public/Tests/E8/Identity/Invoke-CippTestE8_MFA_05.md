SMS, Voice and Email OTP are not phishing-resistant: an attacker who can intercept SMS or proxy a sign-in page can capture the code. ACSC Essential Eight ML2/ML3 requires phasing these out in favour of FIDO2, Windows Hello, or certificate-based authentication.

**Remediation Action**

1. Entra ID > Authentication methods > Policies.
2. Set *SMS*, *Voice call*, and *Email OTP* to Disabled (or restrict to a tightly-scoped group during transition).
3. Make sure users have a phishing-resistant or Authenticator App method registered first.

**Links**
- [Phishing-resistant MFA in Entra ID](https://learn.microsoft.com/en-us/azure/active-directory/authentication/concept-authentication-strengths)
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)

<!--- Results --->
%TestResult%
