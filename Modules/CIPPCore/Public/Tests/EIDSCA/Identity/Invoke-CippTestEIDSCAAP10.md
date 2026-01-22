# Authorization Policy - Users Can Create Apps

Regular users should not be allowed to register applications in Microsoft Entra ID. Application registration should be restricted to authorized administrators who can properly assess security implications and configure applications according to organizational policies.

Allowing unrestricted app registration can lead to shadow IT, misconfigured applications, and potential security vulnerabilities as users may inadvertently create applications with excessive permissions or improper security settings.

**Remediation action**
- [Restrict who can create applications](https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles#restrict-who-can-create-applications)
- [Application and service principal objects in Microsoft Entra ID](https://learn.microsoft.com/entra/identity-platform/app-objects-and-service-principals)
- [Authorization policies in Microsoft Entra ID](https://learn.microsoft.com/graph/api/resources/authorizationpolicy)

<!--- Results --->
%TestResult%
