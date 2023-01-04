using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Interact with query parameters or the body of the request.

$TenantFilter = $Request.Query.TenantFilter
$selectstring = "id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,grouptypes,onPremisesSyncEnabled,resourceProvisioningOptions,userPrincipalName"

if ($Request.Query.GroupID) { 
    $groupid = $Request.query.groupid
    $selectstring = "id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,userPrincipalName"
}
if ($Request.Query.members) { 
    $members = "members"
    $selectstring = "id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule"
}

if ($Request.Query.owners) { 
    $members = "owners"
    $selectstring = "id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule"
}
try {
    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupID)/$($members)?`$top=999&select=$selectstring" -tenantid $TenantFilter  | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split "@" | Select-Object -Last 1 } },
    @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -Like '*Team*') { $true }else { $false } } },
    @{Name = 'calculatedGroupType'; Expression = {

            if ($_.mailEnabled -and $_.securityEnabled) {
                "Mail-Enabled Security"
            }
            if (!$_.mailEnabled -and $_.securityEnabled) {
                "Security"
            }
            if ($_.groupTypes -contains 'Unified') {
                "Microsoft 365"
            }
            if (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (!$_.securityEnabled)) {
                "Distribution List"
            }
        }
    },
    @{Name = 'dynamicGroupBool'; Expression = {
            if ($_.groupTypes -contains 'DynamicMembership') {
                $true
            }
            else {
                $false
            }
        }
    }

    $StatusCode = [HttpStatusCode]::OK
}
catch {
    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
    $StatusCode = [HttpStatusCode]::Forbidden
    $GraphRequest = $ErrorMessage
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    })
