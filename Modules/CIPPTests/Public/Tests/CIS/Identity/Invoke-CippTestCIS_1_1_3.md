Global Administrator is the most powerful role in Microsoft 365. Too few GA accounts removes redundancy when an admin is unavailable; too many widens the blast radius of a compromise.

**Remediation Action**

1. Audit the current GA list and remove any redundant assignments.
2. Migrate role-specific tasks to least-privileged roles (Exchange Admin, User Admin, etc.).
3. Use Privileged Identity Management (PIM) so GA is *eligible*, not *active*, for most accounts.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 1.1.3](https://www.cisecurity.org/benchmark/microsoft_365)
- [Microsoft Entra built-in roles](https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference)

<!--- Results --->
%TestResult%
