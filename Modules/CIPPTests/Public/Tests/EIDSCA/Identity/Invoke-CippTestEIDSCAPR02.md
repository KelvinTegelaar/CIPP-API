# Password Rule Settings - Enable password protection on Windows Server Active Directory

Password protection should be enabled for on-premises Windows Server Active Directory to extend Microsoft Entra password protection to your hybrid environment. This ensures that weak passwords are blocked not only in the cloud but also when users set or change passwords on domain controllers.

Enabling this feature requires deploying Azure AD Password Protection DC agents on your domain controllers and proxy services in your on-premises environment.

**Remediation action**
- [Plan and deploy on-premises Azure Active Directory Password Protection](https://learn.microsoft.com/entra/identity/authentication/howto-password-ban-bad-on-premises-deploy)
- [Enable on-premises Azure Active Directory Password Protection](https://learn.microsoft.com/entra/identity/authentication/howto-password-ban-bad-on-premises-operations)
- [Monitor on-premises Azure Active Directory Password Protection](https://learn.microsoft.com/entra/identity/authentication/howto-password-ban-bad-on-premises-monitor)

<!--- Results --->
%TestResult%
