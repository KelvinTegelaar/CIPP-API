using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

if ($Request.query.TenantFilter -ne 'AllTenants') {

    $users = Get-CIPPMSolUsers -tenant $Request.query.TenantFilter
    $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $Request.query.TenantFilter ).IsEnabled
    $CAState = New-Object System.Collections.ArrayList

    $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $Request.query.TenantFilter -ErrorAction Stop )

    try {
        $ExcludeAllUsers = New-Object System.Collections.ArrayList
        $ExcludeSpecific = New-Object System.Collections.ArrayList

        foreach ($Policy in $CAPolicies) {
            if (($policy.grantControls.builtincontrols -eq 'mfa') -or ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa')) {
                if ($Policy.conditions.applications.includeApplications -ne 'All') {
                    Write-Host $Policy.conditions.applications.includeApplications
                    $CAState.Add("Specific Applications - $($policy.state)") | Out-Null
                    $ExcludeSpecific = $Policy.conditions.users.excludeUsers
                    continue
                }
                if ($Policy.conditions.users.includeUsers -eq 'All') {
                    $CAState.Add("All Users - $($policy.state)") | Out-Null
                    $ExcludeAllUsers = $Policy.conditions.users.excludeUsers
                    continue
                }
            } 
        }
    }
    catch {
    }
    if ($CAState.length -eq 0) { $CAState.Add('None') | Out-Null }
    Try {
        $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $Request.query.TenantFilter)
    }
    catch {
        $CAState.Add('Not Licensed for Conditional Access')
        $MFARegistration = $null
    }
    # Interact with query parameters or the body of the request.
    $GraphRequest = $Users | ForEach-Object {
        Write-Host "Processing users"
        $UserCAState = New-Object System.Collections.ArrayList
        foreach ($CA in $CAState) {
            Write-Host "Looping CAState"
            if ($CA -eq 'All Users') {
                if ($ExcludeAllUsers -contains $_.ObjectId) { $UserCAState.Add('Excluded from All Users') | Out-Null }
                else { $UserCAState.Add($CA) | Out-Null }
            }
            elseif ($CA -eq 'Specific Applications') {
                if ($ExcludeSpecific -contains $_.ObjectId) { $UserCAState.Add('Excluded from Specific Applications') | Out-Null }
                else { $UserCAState.Add($CA) | Out-Null }
            }
            else {
                Write-Host "Adding to CA"
                $UserCAState.Add($CA) | Out-Null
            }
        }

        $PerUser = if ($_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state -ne $null) { $_.StrongAuthenticationRequirements.StrongAuthenticationRequirement.state } else { 'Disabled' }
        $AccountState = if ($_.BlockCredential -eq $true) { $false } else { $true }

        $MFARegUser = if (($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered -eq $null) { $false } else { ($MFARegistration | Where-Object -Property UserPrincipalName -EQ $_.UserPrincipalName).IsMFARegistered }
        [PSCustomObject]@{
            ID              = $_.ObjectId
            UPN             = $_.UserPrincipalName
            DisplayName     = $_.DisplayName
            AccountEnabled  = $AccountState
            PerUser         = $PerUser
            isLicensed      = $_.isLicensed
            MFARegistration = $MFARegUser
            CoveredByCA     = ($UserCAState -join ', ')
            CoveredBySD     = $SecureDefaultsState
        }
    }
}
else {
    $Table = Get-CIPPTable -TableName cachemfa
    $Rows = Get-AzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-2)
    if (!$Rows) {
        Push-OutputBinding -Name Msg -Value (Get-Date).ToString()
        $GraphRequest = [PSCustomObject]@{
            UPN = 'Loading data for all tenants. Please check back in 10 minutes'
        }
    }         
    else {
        $GraphRequest = $Rows
    }
}
# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($GraphRequest)
    })
