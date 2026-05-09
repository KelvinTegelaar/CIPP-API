When user consent is restricted (5.1.5.1) users still need a way to ask for legitimate apps. The admin consent workflow gives them a self-service request path with administrative review.

**Remediation Action**

```powershell
Update-MgPolicyAdminConsentRequestPolicy -IsEnabled $true -NotifyReviewers $true -RemindersEnabled $true -RequestDurationInDays 30 -Reviewers @(@{query='/users/<reviewer-upn>'; queryType='MicrosoftGraph'; queryRoot=$null})
```

**Links**
- [CIS Microsoft 365 Foundations Benchmark v6.0.1 - 5.1.5.2](https://www.cisecurity.org/benchmark/microsoft_365)

<!--- Results --->
%TestResult%
