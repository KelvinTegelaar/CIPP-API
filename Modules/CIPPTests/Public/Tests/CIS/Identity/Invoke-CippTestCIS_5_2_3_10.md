Authenticator Lite embeds a subset of Microsoft Authenticator into companion apps such as Outlook mobile, letting users satisfy MFA without the standalone app. However, it does not show application name or geographic location context in push notifications, does not satisfy Conditional Access authentication strength requirements, and does not support passwordless sign-in or SSPR via push. Disabling Microsoft Authenticator on companion applications ensures users authenticate through the full app where all MFA fatigue defenses are active.

**Remediation Action**

Microsoft Entra > Authentication methods > Policies > Microsoft Authenticator > Configure: set Microsoft Authenticator on companion applications Status to Disabled, then save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.3.10](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
