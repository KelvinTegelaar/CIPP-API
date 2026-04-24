# Password Rule Settings - Lockout duration in seconds

Account lockout duration should be configured to automatically unlock accounts after a specified period following too many failed sign-in attempts. A recommended lockout duration is at least 60 seconds to slow down brute-force attacks while balancing user convenience and security.

The lockout duration determines how long an account remains locked after reaching the lockout threshold, providing temporary protection against automated password guessing attacks.

**Remediation action**
- [Microsoft Entra smart lockout](https://learn.microsoft.com/entra/identity/authentication/howto-password-smart-lockout)
- [Password policies and account restrictions in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/authentication/concept-password-policies)
- [Configure smart lockout thresholds](https://learn.microsoft.com/entra/identity/authentication/howto-password-smart-lockout#configure-smart-lockout)

<!--- Results --->
%TestResult%
