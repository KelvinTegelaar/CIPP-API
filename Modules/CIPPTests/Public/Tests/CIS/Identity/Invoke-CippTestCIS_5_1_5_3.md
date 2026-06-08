Client secrets (password credentials) are static strings with weaker security guarantees than certificates, and they are often stored in plaintext in source code, config files, and CI/CD pipelines. A leaked secret lets any holder authenticate as the application and reach whatever permissions it holds. Blocking new password credentials tenant-wide removes this attack surface for future applications and forces adoption of stronger credential types such as certificates.

**Remediation Action**

In Microsoft Entra admin center, go to Entra ID > Enterprise apps > Security > Application policies, open Block password addition, set Status to On, set Applies to to all applications (with reviewed exclusions if any), and save.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.5.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
