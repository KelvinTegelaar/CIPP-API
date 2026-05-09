A user is "MFA capable" once they have at least one strong authentication method registered. CA policies that require MFA fail-open for users without a registered method, so every member must be MFA capable before MFA enforcement gives full coverage.

**Remediation Action**

1. Use the Microsoft Entra Authentication Methods registration campaign to nudge users.
2. Run the User Registration Details report (`/reports/authenticationMethods/userRegistrationDetails`) and chase any user with `isMfaCapable = false`.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.2.3.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
