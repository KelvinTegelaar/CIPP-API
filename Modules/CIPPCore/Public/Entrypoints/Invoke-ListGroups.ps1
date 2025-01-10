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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.TenantFilter
    $selectstring = "id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,grouptypes,onPremisesSyncEnabled,resourceProvisioningOptions,userPrincipalName&`$expand=members(`$select=userPrincipalName)"

    $BulkRequestArrayList = [System.Collections.ArrayList]@()

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
        $selectstring = 'id,userPrincipalName,displayName,hideFromOutlookClients,hideFromAddressLists,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule'
        $BulkRequestArrayList.add(@{
                id     = 3
                method = 'GET'
                url    = "groups/$($Request.Query.GroupID)/owners?`$top=999&select=$selectstring"
            })
    }

    try {
        if ($BulkRequestArrayList.Count -gt 0) {
            $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequestArrayList) -asapp $true
            $GraphRequest = [PSCustomObject]@{
                groupInfo = ($RawGraphRequest | Where-Object { $_.id -eq 1 }).body
                members   = ($RawGraphRequest | Where-Object { $_.id -eq 2 }).body.value
                owners    = ($RawGraphRequest | Where-Object { $_.id -eq 3 }).body.value
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
