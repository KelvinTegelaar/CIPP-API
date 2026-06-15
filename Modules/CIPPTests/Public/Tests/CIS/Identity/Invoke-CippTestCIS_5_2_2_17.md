Authentication transfer is a flow that lets users seamlessly transfer authenticated state from one device to another, such as scanning a QR code in Outlook desktop to sign into Outlook mobile. Blocking it protects against token theft and replay by preventing device tokens from silently authenticating on other devices or browsers, ensuring each authentication request originates from the original device and remains subject to device compliance and session checks. The recommended state is to block authentication transfer.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass accounts)
- Target resources: All resources (All cloud apps)
- Conditions > Authentication flows: Authentication transfer
- Grant: Block access
- Enable policy: On

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.2.17](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
