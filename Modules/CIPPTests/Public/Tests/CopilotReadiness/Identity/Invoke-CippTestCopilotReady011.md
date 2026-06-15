# Tenant Has Enabled Conditional Access Policies

Conditional Access (CA) policies are the primary enforcement mechanism for access controls in Microsoft Entra ID. Without enabled CA policies, there is no baseline enforcement of MFA at sign-in, no restriction based on device compliance or location, and no signal-based risk evaluation before granting access to M365 resources.

Deploying Microsoft 365 Copilot without CA policies in place increases the risk of unauthorized access to Copilot-generated content and tenant data. At minimum, tenants should have a CA policy requiring MFA for all users before deploying Copilot. Tenants without Azure AD Premium licenses will see this test skipped as CA requires P1 or above.

**Remediation action**
- [Common Conditional Access policies](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-policy-common)
- [Require MFA for all users (CA policy template)](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-mfa-strength)
- [What is Conditional Access?](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
- [Secure access for Copilot deployments](https://learn.microsoft.com/en-us/copilot/microsoft-365/microsoft-365-copilot-privacy)

<!--- Results --->
%TestResult%
