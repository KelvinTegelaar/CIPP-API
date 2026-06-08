Safe Attachments detonates email attachments in a sandbox before delivery and blocks malware that signature scanning misses.

**Remediation Action**

```powershell
New-SafeAttachmentPolicy -Name 'Default Safe Attachments' -Enable $true -Action Block
New-SafeAttachmentRule -Name 'Default Safe Attachments' -SafeAttachmentPolicy 'Default Safe Attachments' -RecipientDomainIs <yourdomain>
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v7.0.0 - 2.1.4](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
