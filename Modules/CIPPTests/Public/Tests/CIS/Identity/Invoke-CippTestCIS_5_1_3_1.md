A dynamic group containing every guest enables guest-aware Conditional Access policies, access reviews and lifecycle automation without manual maintenance.

**Remediation Action**

```powershell
New-MgGroup -DisplayName 'All Guest Users' -SecurityEnabled:$true -MailEnabled:$false -MailNickname 'allguests' -GroupTypes 'DynamicMembership' -MembershipRule '(user.userType -eq "Guest")' -MembershipRuleProcessingState 'On'
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.3.1](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
