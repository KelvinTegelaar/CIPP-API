function Invoke-ListGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    $GroupID = $Request.Query.groupID
    $GroupType = $Request.Query.groupType
    $Members = $Request.Query.members
    $Owners = $Request.Query.owners

    $ExpandMembers = $Request.Query.expandMembers ?? $false

    $SelectString = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,onPremisesSyncEnabled,resourceProvisioningOptions,assignedLicenses,userPrincipalName,licenseProcessingState'
    if ($ExpandMembers -ne $false) {
        $SelectString = '{0}&$expand=members($select=userPrincipalName)' -f $SelectString
    }


    $BulkRequestArrayList = [System.Collections.Generic.List[object]]::new()

    if ($Request.Query.GroupID) {
        $SelectString = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,assignedLicenses,userPrincipalName,onPremisesSyncEnabled,licenseProcessingState'
        $BulkRequestArrayList.add(@{
                id     = 1
                method = 'GET'
                url    = "groups/$($GroupID)?`$select=$SelectString"
            })
    }
    if ($Members) {
        $SelectString = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
        $BulkRequestArrayList.add(@{
                id     = 2
                method = 'GET'
                url    = "groups/$($GroupID)/members?`$top=999&select=$SelectString"
            })
    }

    if ($Owners) {
        if ($GroupType -ne 'Distribution List' -and $GroupType -ne 'Mail-Enabled Security') {
            $SelectString = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
            $BulkRequestArrayList.add(@{
                    id     = 3
                    method = 'GET'
                    url    = "groups/$($GroupID)/owners?`$top=999&select=$SelectString"
                })
        } else {
            $OwnerIds = New-ExoRequest -cmdlet 'Get-DistributionGroup' -tenantid $TenantFilter -cmdParams @{Identity = $GroupID } -Select 'ManagedBy' -useSystemMailbox $true | Select-Object -ExpandProperty ManagedBy

            $BulkRequestArrayList.add(@{
                    id      = 3
                    method  = 'POST'
                    url     = 'directoryObjects/getByIds'
                    body    = @{
                        ids = @($OwnerIds)
                    }
                    headers = @{
                        'Content-Type' = 'application/json'
                    }
                })
        }
    }

    if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
        # get the outside the organization RequireSenderAuthenticationEnabled setting
        $OnlyAllowInternal = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{Identity = $GroupID } -Select 'RequireSenderAuthenticationEnabled' -useSystemMailbox $true | Select-Object -ExpandProperty RequireSenderAuthenticationEnabled
    } elseif ($GroupType -eq 'Microsoft 365') {
        $UnifiedGroupInfo = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-UnifiedGroup' -cmdParams @{Identity = $GroupID } -Select 'RequireSenderAuthenticationEnabled,subscriptionEnabled,AutoSubscribeNewMembers,HiddenFromExchangeClientsEnabled' -useSystemMailbox $true
        $OnlyAllowInternal = $UnifiedGroupInfo.RequireSenderAuthenticationEnabled
    } else {
        $OnlyAllowInternal = $null
    }

    if ($GroupType -eq 'Microsoft 365') {
        if ($UnifiedGroupInfo.subscriptionEnabled -eq $true -and $UnifiedGroupInfo.AutoSubscribeNewMembers -eq $true) { $SendCopies = $true } else { $SendCopies = $false }
    } else {
        $SendCopies = $null
    }

    try {
        if ($BulkRequestArrayList.Count -gt 0) {
            $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequestArrayList) -asapp $true
            $GraphRequest = [PSCustomObject]@{
                groupInfo              = ($RawGraphRequest | Where-Object { $_.id -eq 1 }).body | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split '@' | Select-Object -Last 1 } },
                @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -like '*Team*') { $true } else { $false } } },
                @{Name = 'groupType'; Expression = {
                        if ($_.groupTypes -contains 'Unified') { 'Microsoft 365' }
                        elseif ($_.mailEnabled -and $_.securityEnabled) { 'Mail-Enabled Security' }
                        elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'Security' }
                        elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'Distribution List' }
                    }
                },
                @{Name = 'calculatedGroupType'; Expression = {
                        if ($_.groupTypes -contains 'Unified') { 'm365' }
                        elseif ($_.mailEnabled -and $_.securityEnabled) { 'security' }
                        elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'generic' }
                        elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'distributionList' }
                    }
                },
                @{Name = 'dynamicGroupBool'; Expression = { if ($_.groupTypes -contains 'DynamicMembership') { $true } else { $false } } }
                members                = @(($RawGraphRequest | Where-Object { $_.id -eq 2 }).body.value | Sort-Object displayName)
                owners                 = @(($RawGraphRequest | Where-Object { $_.id -eq 3 }).body.value | Sort-Object displayName)
                allowExternal          = (!$OnlyAllowInternal)
                sendCopies             = $SendCopies
                hideFromOutlookClients = if ($GroupType -eq 'Microsoft 365') { $UnifiedGroupInfo.HiddenFromExchangeClientsEnabled } else { $null }
            }
        } else {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupID)/$($members)?`$top=999&select=$SelectString" -tenantid $TenantFilter | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split '@' | Select-Object -Last 1 } },
            @{Name = 'membersCsv'; Expression = { $_.members.userPrincipalName -join ',' } },
            @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -like '*Team*') { $true }else { $false } } },
            @{Name = 'groupType'; Expression = {
                    if ($_.groupTypes -contains 'Unified') { 'Microsoft 365' }
                    elseif ($_.mailEnabled -and $_.securityEnabled) { 'Mail-Enabled Security' }
                    elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'Security' }
                    elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'Distribution List' }
                }
            },
            @{Name = 'calculatedGroupType'; Expression = {
                    if ($_.groupTypes -contains 'Unified') { 'm365' }
                    elseif ($_.mailEnabled -and $_.securityEnabled) { 'security' }
                    elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'generic' }
                    elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'distributionList' }
                }
            },
            @{Name = 'dynamicGroupBool'; Expression = { if ($_.groupTypes -contains 'DynamicMembership') { $true } else { $false } } }
            $GraphRequest = @($GraphRequest | Sort-Object displayName)
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-Warning $_.InvocationInfo.PositionMessage
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequest
        })

}
