Legacy authentication protocols (POP, IMAP, SMTP AUTH, older Outlook clients, ActiveSync basic auth) cannot enforce MFA. If they are reachable, an attacker with stolen credentials defeats Essential Eight MFA controls.

**Remediation Action**

1. Entra ID > Conditional Access > Create policy.
2. Users: All users (exclude break-glass + service accounts that genuinely need legacy auth).
3. Cloud apps: All cloud apps.
4. Conditions > Client apps: tick *Exchange ActiveSync clients* and *Other clients*.
5. Grant: Block access.
6. Enable.

**Links**
- [Block legacy authentication](https://learn.microsoft.com/en-us/azure/active-directory/conditional-access/howto-conditional-access-policy-block-legacy)
- [ACSC Essential Eight - MFA](https://learn.microsoft.com/en-us/compliance/anz/e8-mfa)

<!--- Results --->
%TestResult%
