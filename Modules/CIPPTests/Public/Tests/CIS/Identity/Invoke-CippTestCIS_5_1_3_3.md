Group owners are standard users who may not understand access-governance requirements. Allowing owners to approve membership requests through My Groups means additions to security or Microsoft 365 groups can occur without administrator review, bypassing formal access provisioning and expanding the blast radius of a compromised account.

**Remediation Action**

Microsoft Entra admin center > Entra ID > Groups > General > set **Owners can manage group membership requests in My Groups** to **No**.

> Manual control — no Graph property is exposed, so CIPP reports this as Informational for manual review.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 5.1.3.3](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
