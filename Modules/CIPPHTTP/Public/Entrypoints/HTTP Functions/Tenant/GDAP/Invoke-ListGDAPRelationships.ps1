function Invoke-ListGDAPRelationships {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    .DESCRIPTION
        Lists GDAP delegated admin relationships with customer tenants, with optional filtering by relationship ID or OData filter.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Id = $Request.Query.id
    $Top = [int]($Request.Query.'$top' ?? 300)
    $Filter = $Request.Query.'$filter'

    try {
        # Enumerate as every configured partner (primary only when the flag is off), tagging
        # each relationship with the partner it came from.
        $Partners = @(Get-CIPPPartnerTenantList)
        $Results = foreach ($Partner in $Partners) {
            try {
                if ($Id) {
                    $Uri = "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$Id"
                    $PartnerResults = New-GraphGetRequest -Uri $Uri -tenantid $Partner.partnerTenantId -NoAuthCheck $true -NoPagination $true -ComplexFilter
                } else {
                    $Uri = "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$top=$Top"
                    if ($Filter) {
                        $Uri = "$Uri&`$filter=$Filter"
                    }
                    $PartnerResults = New-GraphGetRequest -Uri $Uri -tenantid $Partner.partnerTenantId -NoAuthCheck $true -ComplexFilter
                }
                foreach ($Result in $PartnerResults) {
                    $Result | Add-Member -MemberType NoteProperty -Name 'partnerTenantId' -Value $Partner.partnerTenantId -Force
                    $Result | Add-Member -MemberType NoteProperty -Name 'partnerDisplayName' -Value $Partner.displayName -Force
                    $Result | Add-Member -MemberType NoteProperty -Name 'partnerIsPrimary' -Value ([bool]$Partner.IsPrimary) -Force -PassThru
                }
            } catch {
                # An id lookup only exists under one partner - a miss on the others is expected
                if ($Partners.Count -eq 1) { throw }
                if (!$Id) {
                    Write-LogMessage -API $APIName -headers $Request.Headers -message "Failed to list GDAP relationships for partner $($Partner.partnerTenantId): $($_.Exception.Message)" -sev Warning
                }
            }
        }
        if ($Id -and (@($Results) | Measure-Object).Count -eq 0) {
            throw "GDAP relationship $Id was not found under any configured partner tenant."
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
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
