function Invoke-ExecServicePrincipals {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $env:TenantID

    $Success = $true

    $Action = $Request.Query.Action ?? 'Default'
    try {
        switch ($Request.Query.Action) {
            'Create' {
                $BlockList = @(
                    'e9a7fea1-1cc0-4cd9-a31b-9137ca5deedd', # eM Client
                    'ff8d92dc-3d82-41d6-bcbd-b9174d163620', # PerfectData Software
                    'a245e8c0-b53c-4b67-9b45-751d1dff8e6b', # Newsletter Software Supermailer
                    'b15665d9-eda6-4092-8539-0eec376afd59', # rclone
                    'a43e5392-f48b-46a4-a0f1-098b5eeb4757', # CloudSponge
                    'caffae8c-0882-4c81-9a27-d1803af53a40'  # SigParser
                )
                $Action = 'Create'

                if ($Request.Query.AppId -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {

                    if ($BlockList -contains $Request.Query.AppId) {
                        $Results = 'Service Principal creation is blocked for this AppId'
                        $Success = $false
                    } else {
                        $Body = @{
                            'appId' = $Request.Query.AppId
                        } | ConvertTo-Json -Compress
                        try {
                            $ServicePrincipal = New-GraphPostRequest -Uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -type POST -body $Body -NoAuthCheck $true
                            $Results = "Created service principal for $($ServicePrincipal.displayName) ($($ServicePrincipal.appId))"
                        } catch {
                            $Results = "Unable to create service principal: $($_.Exception.Message)"
                            $Success = $false
                        }
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
                } elseif ($Request.Query.Id) {
                    $Action = 'Get'
                    $Results = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/servicePrincipals/$($Request.Query.Id)" -tenantid $TenantFilter -NoAuthCheck $true
                } else {
                    $Action = 'List'
                    $Uri = 'https://graph.microsoft.com/beta/servicePrincipals?$top=999&$orderby=displayName&$count=true'
                    if ($Request.Query.Select) {
                        $Uri = '{0}&$select={1}' -f $Uri, $Request.Query.Select
                    }

                    $Results = New-GraphGetRequest -Uri $Uri -ComplexFilter -tenantid $TenantFilter -NoAuthCheck $true
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

    if ($ServicePrincipal) {
        $Metadata.ServicePrincipal = $ServicePrincipal
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
