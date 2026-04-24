# FIDO2 - Attestation

FIDO2 attestation enforcement should be configured to ensure that only security keys from trusted manufacturers can be registered. Attestation allows Microsoft Entra ID to verify the authenticity and characteristics of FIDO2 security keys during registration, helping prevent the use of compromised or counterfeit devices.

Enforcing attestation provides an additional layer of security by ensuring that only verified, legitimate FIDO2 security keys are used for authentication in your environment.

**Remediation action**
- [Enable passwordless security key sign-in](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-passwordless-security-key)
- [FIDO2 security key authentication method](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-passwordless)
- [Manage authentication methods](https://learn.microsoft.com/entra/identity/authentication/concept-authentication-methods-manage)

<!--- Results --->
%TestResult%
