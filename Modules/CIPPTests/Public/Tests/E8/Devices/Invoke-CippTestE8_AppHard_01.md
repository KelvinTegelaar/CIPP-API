Web browsers are the most-attacked client application in the enterprise. Disable Flash (now removed), Java applets, and reduce drive-by exposure with an enterprise ad-blocker.

**Remediation Action**

1. Intune > Configuration profiles > Settings catalog > Microsoft Edge.
2. Disable plug-ins (`PluginsBlockedForUrls = *`) and Java; deploy an enterprise ad-blocker (uBlock Origin / NoScript / Edge tracking prevention strict).
3. Repeat for Chrome / Firefox where deployed.

**Links**
- [ACSC Essential Eight - User Application Hardening](https://learn.microsoft.com/en-us/compliance/anz/e8-uah)

<!--- Results --->
%TestResult%
