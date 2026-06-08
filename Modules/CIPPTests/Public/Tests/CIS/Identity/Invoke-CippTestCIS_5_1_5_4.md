Long-lived client secrets extend the window of exploitation when a credential is compromised. A secret that stays valid for years and is never rotated remains usable long after it leaks through source code, build logs, or a breach. Enforcing a maximum lifetime of 180 days or less ensures secrets expire regularly, limits how long a stolen credential is usable, and encourages automated rotation.

**Remediation Action**

In Microsoft Entra admin center, go to Entra ID > Enterprise apps > Security > Application policies, open Restrict max password lifetime, set Status to On, set the maximum lifetime to 180 days or less, set Applies to to all applications (with reviewed exclusions if any), and save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.5.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
