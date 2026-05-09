Compromised mailboxes are routinely used to set inbox forwarding rules that exfiltrate every email to attacker infrastructure. Block forwarding at the tenant level.

**Remediation Action**

```powershell
Set-HostedOutboundSpamFilterPolicy -Identity Default -AutoForwardingMode Off
Set-RemoteDomain -Identity Default -AutoForwardEnabled $false
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.2.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
