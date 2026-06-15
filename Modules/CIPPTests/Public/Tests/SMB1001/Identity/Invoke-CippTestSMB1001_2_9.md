SMB1001 (2.9) — Level 4+ — MFA on every account that can access important digital data. In Microsoft 365 the principal data stores are SharePoint Online, OneDrive for Business, and Exchange Online. The strongest implementation is a Conditional Access policy targeting all cloud apps (or specifically these three workloads) requiring MFA.

**Remediation Action**

Deploy a Conditional Access policy:

- **Users**: All users (or those with access to data)
- **Cloud apps**: Office 365 (covers SPO/ODB/EXO) — or All cloud apps
- **Grant**: Require multi-factor authentication

Use CIPP `standards.ConditionalAccessTemplate` with the Microsoft "Require MFA for all users" baseline template.

**Links**
- [SMB1001:2026 Standard](https://dsi.org)
- [Conditional Access app: Office 365](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-cloud-apps#office-365)

<!--- Results --->
%TestResult%
