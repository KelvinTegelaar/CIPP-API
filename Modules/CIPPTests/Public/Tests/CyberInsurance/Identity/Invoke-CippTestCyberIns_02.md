Insurers ask whether MFA is required for remote access such as VPN and RDP. Microsoft 365 only sees a remote access tool when it signs in through Entra ID, so this check lists the Conditional Access policies that require MFA as supporting evidence. The answer itself comes from the MSP.

**Remediation Action**

1. Put the VPN or remote access tool behind Entra ID single sign-on where it supports it, and require MFA with Conditional Access.
2. Otherwise enable MFA in the remote access tool itself and record the tool and method in the attestation.

<!--- Results --->
%TestResult%
