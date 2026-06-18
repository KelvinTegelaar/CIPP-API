PIM for Groups extends just-in-time elevation to group membership, so users only become members of a role-assignable group for a bounded duration. When such groups contain other groups as members instead of direct user assignments, the PIM activation flow is bypassed for everyone in the nested group — they inherit membership at all times rather than going through PIM activation.

Nested groups also obscure the effective access picture. Auditors can no longer determine, from the role-assignable group alone, which users actually hold the role at any given moment.

**Remediation action**

- [Replace nested group memberships with direct user assignments on role-assignable groups](https://learn.microsoft.com/entra/id-governance/privileged-identity-management/concept-pim-for-groups?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
- [Best practices for role-assignable groups](https://learn.microsoft.com/entra/identity/role-based-access-control/groups-concept?wt.mc_id=zerotrustrecommendations_automation_content_cnl_csasci)
<!--- Results --->
%TestResult%
