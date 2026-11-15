function Invoke-ListAdministrativeUnitMembers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Lists the users, groups and devices in an administrative unit.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Object id of the administrative unit.
    $ID = $Request.Query.ID ?? $Request.Body.ID

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Select a single tenant' }
            })
    }
    if ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ID must be the object id of an administrative unit' }
            })
    }

    try {
        $Members = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$ID/members?`$select=id,displayName,userPrincipalName,mail,operatingSystem,accountEnabled&`$top=999" -tenantid $TenantFilter
        $Body = @(foreach ($Member in @($Members)) {
                if (-not $Member.id) { continue }
                [PSCustomObject]@{
                    id                = $Member.id
                    displayName       = $Member.displayName
                    type              = switch -Wildcard ([string]$Member.'@odata.type') {
                        '*user' { 'User' }
                        '*group' { 'Group' }
                        '*device' { 'Device' }
                        default { 'Other' }
                    }
                    userPrincipalName = $Member.userPrincipalName
                    mail              = $Member.mail
                    operatingSystem   = $Member.operatingSystem
                    accountEnabled    = $Member.accountEnabled
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to list the members of administrative unit $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = $Result }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
