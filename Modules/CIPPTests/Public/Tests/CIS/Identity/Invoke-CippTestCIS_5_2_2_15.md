Conditional Access policies can block access from geographic locations that are out-of-scope for the organization or application. Using Conditional Access as a deny list lets an organization block traffic from regions outside its operational scope or legal jurisdiction, significantly reducing exposure to international threat actors and advanced persistent threats. The recommended state is at least one policy that blocks access from untrusted locations while excluding the trusted locations that should remain allowed.

**Remediation Action**

Conditional Access policy:
- Users: All users (exclude break-glass accounts)
- Target resources: All resources (All cloud apps)
- Network > Include: the untrusted locations to block
- Network > Exclude: All trusted locations (or the trusted locations to allow)
- Grant: Block access
- Enable policy: On

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.2.2.15](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
