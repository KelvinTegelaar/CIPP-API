# All Licensed Users Have MFA Registered

Multi-factor authentication (MFA) is a foundational security control for any Microsoft 365 tenant, and it becomes even more critical when deploying Copilot. Microsoft 365 Copilot has broad access to tenant data — including emails, documents, Teams conversations, and meeting transcripts. A compromised account without MFA can be used to extract sensitive organizational information through Copilot at scale.

Ensuring all licensed users have registered an MFA method provides a baseline defence against credential-based attacks. Users not yet registered are at elevated risk of account compromise, and registering MFA is a prerequisite before stronger controls like phishing-resistant authentication can be enforced.

**Remediation action**
- [Require users to register MFA via aka.ms/mfasetup](https://aka.ms/mfasetup)
- [Deploy multifactor authentication](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-getstarted)
- [Conditional Access policy: Require MFA for all users](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-mfa-strength)
- [Authentication methods registration campaign](https://learn.microsoft.com/en-us/entra/identity/authentication/how-to-registration-campaign)

<!--- Results --->
%TestResult%
