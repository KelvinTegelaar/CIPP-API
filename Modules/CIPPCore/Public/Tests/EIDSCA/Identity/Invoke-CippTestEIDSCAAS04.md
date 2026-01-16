# SMS - No Sign-In

SMS should not be allowed as a primary authentication method (sign-in), though it may be used for multi-factor authentication verification. SMS is vulnerable to SIM swap attacks and interception, making it unsuitable as a standalone authentication factor. Organizations should enforce stronger authentication methods for sign-in while potentially allowing SMS only as a second factor.

This configuration prevents users from signing in with SMS alone, which provides better security than allowing SMS-based authentication while still permitting SMS as an MFA option where appropriate.

**Remediation action**
- [Authentication methods in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-methods)
- [SMS-based authentication in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-phone-options)
- [Plan a passwordless authentication deployment](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-passwordless-deployment)

<!--- Results --->
%TestResult%
