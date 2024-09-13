function Invoke-ExecServicePrincipals {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $env:TenantID

    $Success = $true

    $Action = $Request.Query.Action ?? 'Default'
    try {
        switch ($Request.Query.Action) {
            'Create' {
                $Action = 'Create'
                if ($Request.Query.AppId -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                    $Body = @{
                        'appId' = $Request.Query.AppId
                    } | ConvertTo-Json -Compress
                    try {
                        $Results = New-GraphPostRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -type POST -body $Body
                    } catch {
                        $Results = "Unable to create service principal: $($_.Exception.Message)"
                        $Success = $false
                    }
                } else {
                    $Results = 'Invalid AppId'
                    $Success = $false
                }
            }
            default {
                if ($Request.Query.AppId) {
                    $Action = 'Get'
                    $Results = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$($Request.Query.AppId)')" -tenantid $TenantFilter -NoAuthCheck $true
                } else {
                    $Action = 'List'
                    $Results = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999&$orderby=displayName&$count=true' -ComplexFilter -tenantid $TenantFilter -NoAuthCheck $true
                }
            }
        }
    } catch {
        $Results = $_.Exception.Message
        $Success = $false
    }

    $Metadata = @{
        'Action'  = $Action
        'Success' = $Success
    }

    if ($Request.Query.AppId) {
        $Metadata.AppId = $Request.Query.AppId
    }

    $Body = @{
        'Results'  = $Results
        'Metadata' = $Metadata
    }

    $Json = $Body | ConvertTo-Json -Depth 10 -Compress
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Json
        })
}
