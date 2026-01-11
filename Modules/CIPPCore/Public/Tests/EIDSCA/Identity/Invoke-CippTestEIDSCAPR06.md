# Password Rule Settings - Lockout threshold

A lockout threshold should be configured to prevent brute-force password attacks by temporarily locking accounts after a specified number of failed sign-in attempts. A recommended threshold is 10 or fewer failed attempts, which provides strong protection against automated attacks while minimizing the impact on legitimate users who may occasionally mistype their passwords.

Smart lockout in Microsoft Entra ID uses machine learning to distinguish between legitimate users and attackers, helping to prevent legitimate users from being locked out while still protecting against malicious sign-in attempts.

**Remediation action**
- [Microsoft Entra smart lockout](https://learn.microsoft.com/entra/identity/authentication/howto-password-smart-lockout)
- [Password policies and account restrictions in Microsoft Entra ID](https://learn.microsoft.com/entra/identity/authentication/concept-password-policies)
- [Protect user accounts from attacks with Microsoft Entra ID Protection](https://learn.microsoft.com/entra/id-protection/overview-identity-protection)

<!--- Results --->
%TestResult%
