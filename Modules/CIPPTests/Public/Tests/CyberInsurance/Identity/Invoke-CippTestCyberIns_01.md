Insurers ask whether multi-factor authentication is enforced for every user who can reach email. This check counts enabled, licensed member users and how many of them have MFA enforced by Conditional Access, Security Defaults or per-user MFA. It also counts mailboxes that still allow POP, IMAP or SMTP AUTH, because those protocols do not prompt for MFA.

**Remediation Action**

1. Create a Conditional Access policy that requires MFA for all users and all cloud apps, or enable Security Defaults.
2. Block legacy authentication and turn off POP, IMAP and SMTP AUTH on mailboxes that do not need them.

<!--- Results --->
%TestResult%
