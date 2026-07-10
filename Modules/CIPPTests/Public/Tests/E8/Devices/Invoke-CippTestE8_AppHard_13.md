WMI event subscriptions are a stealthy persistence mechanism (ATT&CK T1546.003). This ASR rule blocks creation of new WMI event consumers/filters/bindings.

**Remediation Action**

1. Intune > Endpoint security > Attack surface reduction.
2. Set *Block persistence through WMI event subscription* to **Block**.

**Links**
- [ASR rules reference](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/attack-surface-reduction-rules-reference)

<!--- Results --->
%TestResult%
