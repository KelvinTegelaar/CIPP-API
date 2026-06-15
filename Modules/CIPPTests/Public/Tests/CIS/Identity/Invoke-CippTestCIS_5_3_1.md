Permanent ("Assigned") privileged role assignments expose standing administrative access continuously, whether or not the admin is performing a task. If such an account is compromised, the attacker immediately holds full role permissions with no time boundary. Privileged roles should instead be granted as PIM *eligible* and activated just-in-time, with only approved break-glass accounts (no more than two, in the Global Administrator role) holding a permanent assignment.

**Remediation Action**

Microsoft Entra > Identity governance > Privileged Identity Management > for each standing privileged assignment, set the **Assignment type** to **Eligible** (or remove it). Limit permanent Global Administrator assignments to at most two break-glass accounts, and give service principal assignments a defined end time.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.3.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
