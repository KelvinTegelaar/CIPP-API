Microsoft now blocks VBA macros from the internet by default in supported Office versions, but the policy must be enforced via Office Cloud Policy or Intune ADMX templates to be guaranteed in-tenant. Verify the *Block macros from running in Office files from the Internet* policy is on for Word, Excel, PowerPoint, Visio, and Outlook.

**Remediation Action**

1. Office Cloud Policy Service ([config.office.com](https://config.office.com)) > Customization > Policy configurations.
2. Search **Block macros from running in Office files from the Internet**.
3. Enable for each Office app and assign to all users.

**Links**
- [Macros from the internet are blocked by default in Office](https://learn.microsoft.com/en-us/deployoffice/security/internet-macros-blocked)

<!--- Results --->
%TestResult%
