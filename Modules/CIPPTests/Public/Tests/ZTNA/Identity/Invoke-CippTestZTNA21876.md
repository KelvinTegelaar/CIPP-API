Standing (permanent) assignments to privileged Microsoft Entra roles such as Global Administrator, Privileged Role Administrator, or Security Administrator expand the blast radius of a single account compromise. A threat actor who acquires credentials for an account with a permanent privileged assignment immediately inherits the full role, with no MFA challenge, approval workflow, or time bound on the access.

Privileged Identity Management (PIM) replaces permanent assignments with just-in-time eligibility. Users must request and activate the role for a bounded duration, typically with MFA and optionally with approval. This shrinks the window of opportunity for an attacker and produces audit trails on every elevation.

**Remediation action**

- [Convert standing privileged role assignments to eligible PIM assignments](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-how-to-add-role-to-user?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
- [Configure PIM role settings](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/pim-how-to-change-default-settings?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
<!--- Results --->
%TestResult%
