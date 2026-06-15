Token Protection is a Conditional Access session control that reduces token replay attacks by ensuring only device-bound sign-in session tokens, such as Primary Refresh Tokens, are accepted when applications request access to protected resources. Because the token is cryptographically bound to a registered device, a stolen token cannot be replayed from another device. The recommended state is to enforce Token Protection for Office 365 Exchange Online, SharePoint Online and Microsoft Teams Services.

**Remediation Action**

Conditional Access policy:
- Users: selected users/groups (exclude break-glass accounts)
- Target resources: Office 365 Exchange Online, SharePoint Online, Microsoft Teams Services
- Conditions > Device platforms: Windows
- Conditions > Client apps: Mobile apps and desktop clients
- Session: Require token protection for sign-in sessions
- Enable policy: On

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.2.16](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
