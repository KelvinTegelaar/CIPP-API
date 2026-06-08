Entra ID Conditional Access lets an organization define named locations - either geographic locations or specific IP addresses and ranges - and mark IP-based locations as trusted. Defining and applying named locations lets policies tailor access requirements based on whether a sign-in originates from a trusted or untrusted network, and improves the accuracy of Entra ID Protection risk evaluations. The recommended state is to define at least one named location and reference it in a Conditional Access policy.

**Remediation Action**

1. Define a named location under Entra ID > Conditional Access > Named locations (for IP ranges, mark as trusted).
2. Reference that named location in the location conditions of at least one enabled Conditional Access policy.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.2.14](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
