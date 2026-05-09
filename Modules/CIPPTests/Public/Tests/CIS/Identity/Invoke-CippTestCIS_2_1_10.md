DMARC tells receiving servers what to do with mail that fails SPF/DKIM and provides reporting of authentication failures. Without DMARC the protective value of SPF and DKIM is significantly reduced.

**Remediation Action**

Publish a TXT record at `_dmarc.<domain>` with at least:

```
v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@<domain>
```

Move to `p=reject` after monitoring DMARC reports.

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.10](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
