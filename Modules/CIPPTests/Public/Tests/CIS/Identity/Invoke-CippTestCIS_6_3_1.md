Outlook add-ins can read mailbox contents and exfiltrate data via outbound HTTP. Removing self-service add-in installation forces every add-in through admin review.

**Remediation Action**

Remove the three add-in roles from every role assignment policy:

```powershell
Get-RoleAssignmentPolicy | ForEach-Object {
    Remove-ManagementRoleAssignment -Identity ("$($_.Name)\My Custom Apps") -Confirm:$false
    Remove-ManagementRoleAssignment -Identity ("$($_.Name)\My Marketplace Apps") -Confirm:$false
    Remove-ManagementRoleAssignment -Identity ("$($_.Name)\My ReadWriteMailbox Apps") -Confirm:$false
}
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 6.3.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
