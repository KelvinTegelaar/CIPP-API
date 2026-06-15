# MS Authenticator - OTP Disabled

Software OATH tokens (time-based one-time passwords) in Microsoft Authenticator should be disabled in favor of push notifications, which provide stronger security and better user experience. Push notifications include additional context about the authentication request and are more resistant to phishing attacks compared to OTP codes that can be phished.

Disabling OTP while keeping push notifications enabled encourages users to adopt the more secure authentication method while maintaining strong MFA protection.

**Remediation action**
- [Microsoft Authenticator authentication method](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-authenticator-app)
- [Authentication methods in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-methods)
- [Plan a passwordless authentication deployment](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-passwordless-deployment)

<!--- Results --->
%TestResult%
