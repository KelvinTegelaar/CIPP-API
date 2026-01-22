# Authorization Policy - Self-Service Password Reset for Admins

Administrators should not be allowed to use self-service password reset (SSPR) for enhanced security. Admin accounts require more stringent security controls and should follow formal password reset procedures that involve additional verification steps rather than self-service options. This ensures that administrative account password resets are properly audited and controlled.

Allowing administrators to use SSPR increases the risk of account compromise, as SSPR methods may be vulnerable to social engineering or other attacks. Administrative accounts have elevated privileges and require the highest level of security protection.

**Remediation action**
- [Manage user settings for Microsoft Entra multifactor authentication](https://learn.microsoft.com/entra/identity/authentication/howto-mfa-userdevicesettings)
- [Plan a Microsoft Entra self-service password reset deployment](https://learn.microsoft.com/entra/identity/authentication/howto-sspr-deployment)
- [Microsoft Entra built-in roles](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference)

<!--- Results --->
%TestResult%
