function Invoke-ListGDAPRelationships {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Id = $Request.Query.id
    $Top = [int]($Request.Query.'$top' ?? 300)
    $Filter = $Request.Query.'$filter'

    try {
        if ($Id) {
            $Uri = "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id"
            $Results = New-GraphGetRequest -Uri $Uri -tenantid $env:TenantID -NoAuthCheck $true -NoPagination $true -ComplexFilter
        } else {
            $Uri = "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$top=$Top"
            if ($Filter) {
                $Uri = "$Uri&`$filter=$Filter"
            }
            $Results = New-GraphGetRequest -Uri $Uri -tenantid $env:TenantID -NoAuthCheck $true -NoPagination $true -ComplexFilter
        }

        $Body = @{
            Results = @($Results)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorContext = if ($Id) { "get GDAP relationship $Id" } else { 'list GDAP relationships' }
        Write-LogMessage -API $APIName -tenant $env:TenantID -headers $Request.Headers -message "Failed to $ErrorContext $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Body = @{ Results = @(); Error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
