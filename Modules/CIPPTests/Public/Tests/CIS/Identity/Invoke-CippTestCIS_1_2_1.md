Public Microsoft 365 groups expose their contents (files, conversations, calendar) to every user in the tenant. Without governance, sensitive material can be exposed to anyone with a tenant account.

**Remediation Action**

1. Audit each public group and confirm its contents are intentional.
2. Set unapproved groups to Private: `Set-UnifiedGroup -Identity <group> -AccessType Private`.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.2.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
