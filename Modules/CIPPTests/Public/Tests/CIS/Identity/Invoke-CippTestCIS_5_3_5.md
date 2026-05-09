Privileged Role Administrator can hand out *any* Entra role. An attacker who activates this role unilaterally can grant themselves Global Administrator. Approval gating is essential.

**Remediation Action**

Microsoft Entra > PIM > Microsoft Entra roles > Privileged Role Administrator > Settings: Require approval = Yes.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.3.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
