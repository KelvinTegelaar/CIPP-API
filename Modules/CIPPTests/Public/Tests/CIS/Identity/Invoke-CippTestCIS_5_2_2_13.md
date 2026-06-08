Sign-in frequency defines how long before a user must reauthenticate to access a resource. The Entra ID default is a rolling 90-day window, which extends the lifespan of stolen tokens or compromised credentials. Enforcing periodic reauthentication of 7 days or less for all users limits that exposure while keeping reauthentication prompts infrequent enough to avoid user fatigue.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass accounts)
- Target resources: All resources (All cloud apps)
- Session > Sign-in frequency: Periodic reauthentication set to 7 days or less
- Enable policy: On

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.2.13](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
