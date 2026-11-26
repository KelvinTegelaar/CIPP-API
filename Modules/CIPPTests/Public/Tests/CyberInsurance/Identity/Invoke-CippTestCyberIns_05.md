Insurers ask whether the backup system requires MFA. Microsoft 365 only sees a backup portal when it signs in through Entra ID, so this check lists enterprise apps whose name looks like a backup product as supporting evidence. The answer itself comes from the MSP.

**Remediation Action**

1. Put the backup portal behind Entra ID single sign-on where it supports it, and require MFA with Conditional Access.
2. Otherwise enable MFA in the backup product itself and record the product and method in the attestation.

<!--- Results --->
%TestResult%
