using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$users = Get-CIPPMSolUsers -tenant $Request.query.TenantFilter
$SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Request.query.TenantFilter ).IsEnabled
$CAState = New-Object System.Collections.ArrayList
$CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies' -tenantid $Request.query.TenantFilter )

try {
    $ExcludeAllUsers = New-Object System.Collections.ArrayList
    $ExcludeSpecific = New-Object System.Collections.ArrayList

    foreach ($Policy in $CAPolicies) {
        if (($policy.grantControls.builtincontrols -eq 'mfa') -or ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa')) {
            if ($Policy.conditions.applications.includeApplications -ne 'All') {
                Write-Host $Policy.conditions.applications.includeApplications
                $CAState.Add('Specific Applications') | Out-Null
                $ExcludeSpecific = $Policy.conditions.users.excludeUsers
                continue
            }
            if ($Policy.conditions.users.includeUsers -eq 'All') {
                $CAState.Add('All Users') | Out-Null
                $ExcludeAllUsers = $Policy.conditions.users.excludeUsers
                continue
            }
        } 
    }
}
catch {}
if (($CAState | Measure-Object | Select-Object -ExpandProperty Count) -eq 0) { $CAState.Add('None') | Out-Null }
Try {
    $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $Request.query.TenantFilter)
}
catch {
    $MFARegistration = $null
}
# Interact with query parameters or the body of the request.
$GraphRequest = $Users | ForEach-Object {
    $UserCAState = New-Object System.Collections.ArrayList
    foreach ($CA in $CAState) {
        if ($CA -eq 'All Users') {
            if ($ExcludeAllUsers -contains $_.ObjectId) { $UserCAState.Add('Excluded from All Users') | Out-Null }
            else { $UserCAState.Add($CA) | Out-Null }
        }
        elseif ($CA -eq 'Specific Applications') {
            if ($ExcludeSpecific -contains $_.ObjectId) { $UserCAState.Add('Excluded from Specific Applications') | Out-Null }
            else { $UserCAState.Add($CA) | Out-Null }
        }
        else {
            $UserCAState.Add($CA) | Out-Null
        }
    }

    $PerUser = if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -ne $null) { $_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state } else { 'Disabled' }
    $AccountState = if ($_.BlockCredential -eq $true) { $false } else { $true }

    $MFARegUser = if (($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered -eq $null) { $false } else { ($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered }
    [PSCustomObject]@{
        UPN             = $_.UserPrincipalName
        AccountEnabled  = $AccountState
        PerUser         = $PerUser
        MFARegistration = $MFARegUser
        CoveredByCA     = ($UserCAState -join ', ')
        CoveredBySD     = $SecureDefaultsState
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })