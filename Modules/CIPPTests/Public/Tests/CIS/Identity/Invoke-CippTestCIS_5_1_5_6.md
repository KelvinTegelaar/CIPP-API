Long-lived certificates extend the window of exploitation when a credential is compromised. A certificate valid for years that is never rotated stays usable long after its private key is exposed through a server breach, misconfigured storage, or a supply-chain compromise. Enforcing a maximum lifetime of 180 days or less ensures certificates expire regularly, limits how long a stolen credential is usable, and encourages automated certificate rotation.

**Remediation Action**

In Microsoft Entra admin center, go to Entra ID > Enterprise apps > Security > Application policies, open Restrict max certificate lifetime, set Status to On, set the maximum lifetime (in days) to 180 or less, set Applies to to all applications (with reviewed exclusions if any), and save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.5.6](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
