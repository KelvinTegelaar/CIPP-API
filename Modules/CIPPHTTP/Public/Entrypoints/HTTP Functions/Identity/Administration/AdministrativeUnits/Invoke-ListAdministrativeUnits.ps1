function Invoke-ListAdministrativeUnits {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Lists the administrative units of a tenant with their membership type, dynamic rule, visibility and whether
        management is restricted to roles scoped to the unit. Pass an ID to read one unit.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Object id of one administrative unit; leave out to list them all.
    $ID = $Request.Query.ID ?? $Request.Body.ID

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Select a single tenant' }
            })
    }
    if ($ID -and -not (Test-IsGuid -String $ID)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ID must be the object id of an administrative unit' }
            })
    }

    # beta: isMemberManagementRestricted and the dynamic membership fields are read from the same object there.
    $Select = 'id,displayName,description,visibility,membershipType,membershipRule,membershipRuleProcessingState,isMemberManagementRestricted'
    try {
        $Units = if ($ID) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/administrativeUnits/$($ID)?`$select=$Select" -tenantid $TenantFilter
        } else {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directory/administrativeUnits?`$select=$Select&`$top=999" -tenantid $TenantFilter
        }
        $Body = @(foreach ($Unit in @($Units)) {
                if (-not $Unit.id) { continue }
                [PSCustomObject]@{
                    id                            = $Unit.id
                    displayName                   = $Unit.displayName
                    description                   = $Unit.description
                    # Graph leaves visibility null for a public unit.
                    visibility                    = if ($Unit.visibility) { $Unit.visibility } else { 'Public' }
                    membershipType                = if ($Unit.membershipType) { $Unit.membershipType } else { 'Assigned' }
                    membershipRule                = $Unit.membershipRule
                    membershipRuleProcessingState = $Unit.membershipRuleProcessingState
                    isMemberManagementRestricted  = [bool]$Unit.isMemberManagementRestricted
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to list administrative units: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = $Result }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
