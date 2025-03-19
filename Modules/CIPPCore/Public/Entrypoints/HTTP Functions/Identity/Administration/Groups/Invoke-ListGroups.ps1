using namespace System.Net

Function Invoke-ListGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.TenantFilter
    $selectstring = "id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,grouptypes,onPremisesSyncEnabled,resourceProvisioningOptions,userPrincipalName&`$expand=members(`$select=userPrincipalName)"

    $BulkRequestArrayList = [System.Collections.Generic.List[object]]::new()

    if ($Request.Query.GroupID) {
        $selectstring = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,userPrincipalName'
        $BulkRequestArrayList.add(@{
                id     = 1
                method = 'GET'
                url    = "groups/$($Request.Query.GroupID)?`$select=$selectstring"
            })
    }
    if ($Request.Query.members) {
        $selectstring = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
        $BulkRequestArrayList.add(@{
                id     = 2
                method = 'GET'
                url    = "groups/$($Request.Query.GroupID)/members?`$top=999&select=$selectstring"
            })
    }

    if ($Request.Query.owners) {
        if ($Request.Query.groupType -ne 'Distribution List' -and $Request.Query.groupType -ne 'Mail-Enabled Security') {
            $selectstring = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
            $BulkRequestArrayList.add(@{
                    id     = 3
                    method = 'GET'
                    url    = "groups/$($Request.Query.GroupID)/owners?`$top=999&select=$selectstring"
                })
        } else {
            $OwnerIds = New-ExoRequest -cmdlet 'Get-DistributionGroup' -tenantid $TenantFilter -cmdParams @{Identity = $Request.Query.GroupID } -useSystemMailbox $true | Select-Object -ExpandProperty ManagedBy

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

    if ($Request.Query.groupType -eq 'Distribution List' -or $Request.Query.groupType -eq 'Mail-Enabled Security') {
        # get the outside the organization RequireSenderAuthenticationEnabled setting
        $OnlyAllowInternal = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{Identity = $Request.Query.GroupID } -useSystemMailbox $true | Select-Object -ExpandProperty RequireSenderAuthenticationEnabled
    } elseif ($GroupType -eq 'Microsoft 365') {
        $OnlyAllowInternal = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-UnifiedGroup' -cmdParams @{Identity = $Request.Query.GroupID } -useSystemMailbox $true | Select-Object -ExpandProperty RequireSenderAuthenticationEnabled
    } else {
        $OnlyAllowInternal = $null
    }

    if ($Request.Query.groupType -eq 'Microsoft 365') {
        $UnifiedGroup = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-UnifiedGroup' -cmdParams @{Identity = $Request.Query.GroupID } -useSystemMailbox $true | Select-Object -Property subscriptionEnabled, AutoSubscribeNewMembers

        if ($UnifiedGroup.subscriptionEnabled -eq $true -and $UnifiedGroup.AutoSubscribeNewMembers -eq $true) {
            $SendCopies = $true
        } else {
            $SendCopies = $false
        }
    } else {
        $SendCopies = $null
    }

    try {
        if ($BulkRequestArrayList.Count -gt 0) {
            $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequestArrayList) -asapp $true
            $GraphRequest = [PSCustomObject]@{
                groupInfo     = ($RawGraphRequest | Where-Object { $_.id -eq 1 }).body
                members       = ($RawGraphRequest | Where-Object { $_.id -eq 2 }).body.value
                owners        = ($RawGraphRequest | Where-Object { $_.id -eq 3 }).body.value
                allowExternal = (!$OnlyAllowInternal)
                sendCopies    = $SendCopies
            }
        } else {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupID)/$($members)?`$top=999&select=$selectstring" -tenantid $TenantFilter | Select-Object *, @{ Name = 'primDomain'; Expression = { $_.mail -split '@' | Select-Object -Last 1 } },
            @{Name = 'membersCsv'; Expression = { $_.members.userPrincipalName -join ',' } },
            @{Name = 'teamsEnabled'; Expression = { if ($_.resourceProvisioningOptions -Like '*Team*') { $true }else { $false } } },
            @{Name = 'calculatedGroupType'; Expression = {

                    if ($_.mailEnabled -and $_.securityEnabled) {
                        'Mail-Enabled Security'
                    }
                    if (!$_.mailEnabled -and $_.securityEnabled) {
                        'Security'
                    }
                    if ($_.groupTypes -contains 'Unified') {
                        'Microsoft 365'
                    }
                    if (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (!$_.securityEnabled)) {
                        'Distribution List'
                    }
                }
            },
            @{Name = 'dynamicGroupBool'; Expression = {
                    if ($_.groupTypes -contains 'DynamicMembership') {
                        $true
                    } else {
                        $false
                    }
                }
            }
            $GraphRequest = @($GraphRequest | Sort-Object displayName)
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-Warning $_.InvocationInfo.PositionMessage
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $GraphRequest
        })

}
