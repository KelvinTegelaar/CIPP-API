Shared mailboxes have a backing user account. If that account is enabled, an attacker who recovers or resets the password can sign in directly. Microsoft's recommendation is to keep shared mailbox sign-in disabled and access them through delegation only.

**Remediation Action**

1. Disable sign-in: `Update-MgUser -UserId <id> -AccountEnabled:$false` for every SharedMailbox account.
2. Access shared mailboxes via delegated permissions or SendAs/SendOnBehalf.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.2.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
