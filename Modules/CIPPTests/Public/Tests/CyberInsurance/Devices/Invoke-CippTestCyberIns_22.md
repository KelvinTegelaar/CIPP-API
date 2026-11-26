Insurers ask for the maximum number of days it takes to deploy critical patches. This check reads each Windows Update ring in Intune and adds the quality update deferral, the install deadline and the grace period to give the longest configured time. The application asks for a number, so this check reports it without a pass or fail.

**Remediation Action**

1. Set a quality update deadline on every update ring so the install is enforced.
2. Keep deferral plus deadline plus grace period within the number of days stated on the application.

<!--- Results --->
%TestResult%
