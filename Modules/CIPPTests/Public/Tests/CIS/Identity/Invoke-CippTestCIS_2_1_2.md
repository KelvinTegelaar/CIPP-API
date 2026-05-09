The Common Attachment Types Filter blocks attachments with extensions known to be commonly used for malware (`.exe`, `.dll`, `.ace`, `.bat`, etc.).

**Remediation Action**

```powershell
Set-MalwareFilterPolicy -Identity Default -EnableFileFilter $true
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 2.1.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
