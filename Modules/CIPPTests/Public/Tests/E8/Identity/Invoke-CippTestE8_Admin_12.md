Microsoft and ACSC recommend a minimum of 2 and a maximum of 4 Global Administrators. Two is the minimum to avoid total lockout; more than four needlessly increases attack surface.

**Remediation Action**

1. Identify excess Global Administrators in Entra ID > Roles and administrators > Global Administrator.
2. Replace with least-privileged roles (e.g. *Exchange Administrator*, *User Administrator*).
3. If fewer than 2 — add a second cloud-only break-glass GA.

**Links**
- [Best practices for roles in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/best-practices)

<!--- Results --->
%TestResult%
