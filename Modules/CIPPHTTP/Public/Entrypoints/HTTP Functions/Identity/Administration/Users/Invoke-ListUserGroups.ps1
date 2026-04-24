function Invoke-ListUserGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.userId
    $URI = "https://graph.microsoft.com/beta/users/$UserID/memberOf/$/microsoft.graph.group?`$select=id,displayName,mailEnabled,securityEnabled,groupTypes,onPremisesSyncEnabled,mail,isAssignableToRole&`$orderby=displayName asc"
    Write-Host $URI

    $GraphRequest = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -Verbose | Select-Object id,
    @{ Name = 'DisplayName'; Expression = { $_.displayName } },
    @{ Name = 'MailEnabled'; Expression = { $_.mailEnabled } },
    @{ Name = 'Mail'; Expression = { $_.mail } },
    @{ Name = 'SecurityGroup'; Expression = { $_.securityEnabled } },
    @{ Name = 'GroupTypes'; Expression = { $_.groupTypes -join ',' } },
    @{ Name = 'OnPremisesSync'; Expression = { $_.onPremisesSyncEnabled } },
    @{ Name = 'IsAssignableToRole'; Expression = { $_.isAssignableToRole } },
    @{ Name = 'calculatedGroupType'; Expression = {
            if ($_.groupTypes -contains 'Unified') { 'Microsoft 365' }
            elseif ($_.mailEnabled -and $_.securityEnabled) { 'Mail-Enabled Security' }
            elseif (-not $_.mailEnabled -and $_.securityEnabled) { 'Security' }
            elseif (([string]::isNullOrEmpty($_.groupTypes)) -and ($_.mailEnabled) -and (-not $_.securityEnabled)) { 'Distribution List' }
        }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
