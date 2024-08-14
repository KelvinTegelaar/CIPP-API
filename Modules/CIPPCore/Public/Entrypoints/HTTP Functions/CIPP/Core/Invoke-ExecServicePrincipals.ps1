function Invoke-ExecServicePrincipals {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $env:TenantId

    $Success = $true

    $Action = $Request.Query.Action ?? 'Default'
    try {
        switch ($Request.Query.Action) {
            'Create' {
                $Body = @{
                    'appId' = $Request.Query.AppId
                } | ConvertTo-Json -Compress
                $Results = New-GraphPostRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -type POST -body $Body
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
