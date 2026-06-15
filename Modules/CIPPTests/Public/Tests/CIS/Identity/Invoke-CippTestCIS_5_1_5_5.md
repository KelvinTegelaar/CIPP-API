Custom password values chosen by the caller are prone to low entropy, predictable patterns, and reuse across applications, making a compromised secret trivial to exploit. System-generated passwords use random values of sufficient length and complexity that resist brute-force and dictionary attacks. Blocking custom passwords removes the weakest credential creation path and ensures every new client secret meets a consistent entropy baseline.

**Remediation Action**

In Microsoft Entra admin center, go to Entra ID > Enterprise apps > Security > Application policies, open Block custom passwords, set Status to On, set Applies to to all applications (with reviewed exclusions if any), and save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.5.5](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
