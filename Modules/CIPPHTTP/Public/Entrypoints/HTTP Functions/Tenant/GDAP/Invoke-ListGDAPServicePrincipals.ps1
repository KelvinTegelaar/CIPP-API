function Invoke-ListGDAPServicePrincipals {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    $OwnerType = ($Request.Query.ownerType ?? 'partner').ToLowerInvariant()
    $Top = [int]($Request.Query.'$top' ?? 999)

    $Filter = $null
    switch ($OwnerType) {
        'partner' {
            $Filter = "appOwnerOrganizationId eq $($env:TenantID)"
        }
        'vendor' {
            $VendorTenantIdsRaw = $Request.Query.vendorTenantIds ?? ''
            $VendorTenantIds = @(
                $VendorTenantIdsRaw -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object {
                        -not [string]::IsNullOrWhiteSpace($_) -and ([guid]::TryParse($_, [ref][guid]::Empty))
                    }
            )

            if ($VendorTenantIds.Count -eq 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        Body       = @{ Results = @() }
                    })
            }

            $Filter = 'appOwnerOrganizationId in ({0})' -f ($VendorTenantIds -join ',')
        }
        default {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = @(); Error = "Unsupported ownerType '$OwnerType'" }
                })
        }
    }

    $Select = 'id,displayName,appId,appOwnerOrganizationId'
    $Uri = "https://graph.microsoft.com/beta/servicePrincipals?`$top=$Top&`$select=$Select&`$count=true&`$filter=$Filter"

    try {
        $Results = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter -NoPagination $true -ComplexFilter

        $Body = @{
            Results = @($Results)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Request.Headers -message "Failed to list GDAP service principals: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Body = @{ Results = @(); Error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
