using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


        $svcPrincipalGraphAPI = Invoke-RestMethod -Method GET -Headers $Graphheader -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')"
        $svcPrincipalSharepointAPI = Invoke-RestMethod -Method GET -Headers $Graphheader -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0ff1-ce00-000000000000')"

        # If the Sharepoint management app service principal does not yet exist then create it

        $svcPrincipalSPmgmt = Invoke-RestMethod -Method POST -Headers $Graphheader -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" -Body '{ "appId": "5d961ae3-af69-4598-873f-3caa27d58a46" }' -ContentType "application/Json"

        # if the app svc principal exists, consent app permissions
        if ($svcPrincipalSPmgmt) {
        $grants = @(
                [pscustomobject]@{
                principalId     = $($svcPrincipalSPmgmt.id)
                resourceId      = $($svcPrincipalGraphAPI.id)
                appRoleId       = "a82116e5-55eb-4c41-a434-62fe8a61c773"
                } # Graph Sites.FullControl.All
                [pscustomobject]@{
                principalId     = $($svcPrincipalSPmgmt.id)
                resourceId      = $($svcPrincipalGraphAPI.id)
                appRoleId       = "f12eb8d6-28e3-46e6-b2c0-b7e4dc69fc95"
                } # Graph TermStore.ReadWrite.All
                [pscustomobject]@{
                principalId     = $($svcPrincipalSPmgmt.id)
                resourceId      = $($svcPrincipalSharepointAPI.id)
                appRoleId       = "678536fe-1083-478a-9c59-b99265e6b0d3"
                } # Sharepoint API Sites.FullControl.All
                [pscustomobject]@{
                principalId     = $($svcPrincipalSPmgmt.id)
                resourceId      = $($svcPrincipalSharepointAPI.id)
                appRoleId       = "c8e3537c-ec53-43b9-bed3-b2bd3617ae97"
                } # Sharepoint API TermStore.ReadWrite.All
        )

        foreach ($grant in $grants) {
                try {
                Invoke-RestMethod -Method POST -Headers $Graphheader -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($svcPrincipalSPmgmt.id)/appRoleAssignedTo" -Body ($grant | ConvertTo-Json) -ContentType "application/Json"
                } catch {
                
                }
        }
        Write-Output "Tenant has been consented: $($Tenant.defaultDomainName) | $($tenant.TenantId)"
        }

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @("Executed")
    }) -clobber