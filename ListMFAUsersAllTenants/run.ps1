# Input bindings are passed in via param block.
param([string] $QueueItem, $TriggerMetadata)

# Write out the queue message and metadata to the information log.
Write-Host "PowerShell queue trigger function processed work item: $QueueItem"

$GraphRequest = Get-Tenants | ForEach-Object -Parallel { 
    $domainName = $_.defaultDomainName
    $tenantName = $_.displayName
    Import-Module '.\GraphHelper.psm1'
    $Table = Get-CIPPTable -TableName cachemfa

    try {
        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
        $users = Get-CIPPMSolUsers -tenant $domainName
        $SecureDefaultsState = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/identitySecurityDefaultsEnforcementPolicy' -tenantid $domainName).IsEnabled
        $CAState = New-Object System.Collections.ArrayList
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -tenantid $domainName -ErrorAction Stop )
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
        catch {
        }
        Try {
            $MFARegistration = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails' -tenantid $domainName)
        }
        catch {
            $CAState.Add('Not Licensed for Conditional Access') | Out-Null
            $MFARegistration = $null
        }
        if ($CAState.length -eq 0) { $CAState.Add('None') | Out-Null }

        # Interact with query parameters or the body of the request.
        $GraphRequest = $Users | ForEach-Object {
            try {
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
                @{
                    Tenant          = "$tenantName"
                    UPN             = "$($_.UserPrincipalName)"
                    AccountEnabled  = [boolean]$AccountState
                    PerUser         = "$PerUser"
                    isLicensed      = [boolean]$_.isLicensed
                    MFARegistration = [boolean]$MFARegUser
                    CoveredByCA     = [string]($UserCAState -join ', ')
                    CoveredBySD     = [boolean]$SecureDefaultsState
                    RowKey          = [string]($_.UserPrincipalName).replace('#', '')
                    PartitionKey    = 'users'
                }
            }
            catch {
                @{
                    Tenant          = "$tenantName"
                    UPN             = "$($_.UserPrincipalName)"
                    AccountEnabled  = [boolean]$AccountState
                    isLicensed      = [boolean]$_.isLicensed
                    PerUser         = "$PerUser"
                    MFARegistration = [boolean]$MFARegUser
                    CoveredByCA     = [string]($UserCAState -join ', ')
                    CoveredBySD     = [boolean]$SecureDefaultsState
                    RowKey          = [string]$_.UserPrincipalName
                    PartitionKey    = 'users'
                }
            }
        }
        Write-Host $tenantName
        Write-Host ($GraphRequest | ConvertTo-Json -Compress)
        Add-AzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null

    }
    catch {
        
        $Table = Get-CIPPTable -TableName cachemfa
        @{
            Tenant          = [string]$tenantName
            UPN             = [string]$domainName
            AccountEnabled  = "none"
            PerUser         = "none"
            MFARegistration = "none"
            CoveredByCA     = [string]"Could not connect to tenant"
            CoveredBySD     = "none"
            RowKey          = [string]"$domainName"
            PartitionKey    = 'users'
        }
        Add-AzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null

    } 
}

