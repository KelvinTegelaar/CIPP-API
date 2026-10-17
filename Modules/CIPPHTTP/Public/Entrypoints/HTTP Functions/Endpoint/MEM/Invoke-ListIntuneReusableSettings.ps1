function Invoke-ListIntuneReusableSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists Intune reusable policy settings for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $SettingId = $Request.Query.ID
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body = @{ Results = 'tenantFilter is required' }
        })
    }

    try {
        if (-not $SettingId -and ($TenantFilter -eq 'AllTenants' -or $UseReportDB)) {
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [System.Net.HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'IntuneReusableSettings' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPIntuneReusableSettingsReport -TenantFilter $Tenant -ErrorAction Stop }
                        })
                }
                $Settings = Get-CIPPIntuneReusableSettingsReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [System.Net.HttpStatusCode]::OK
            } catch {
                $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                $Settings = $_.Exception.Message
            }
            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($Settings)
                })
        }

        $baseUri = 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings'
        $selectFields = @(
            'id'
            'settingInstance'
            'displayName'
            'description'
            'settingDefinitionId'
            'version'
            'referencingConfigurationPolicyCount'
            'createdDateTime'
            'lastModifiedDateTime'
        )
        $selectQuery = '?$select=' + ($selectFields -join ',')
        $uri = if ($SettingId) { "$baseUri/$SettingId$selectQuery" } else { "$baseUri$selectQuery" }

        $Settings = New-GraphGetRequest -uri $uri -tenantid $TenantFilter
        if (-not $Settings) { $Settings = @() }

        $Settings = @($Settings) | Where-Object { $_ } | ForEach-Object {
            $setting = $_

            $rawJson = $null
            try {
                $rawJson = $setting | ConvertTo-Json -Depth 50 -Compress -ErrorAction Stop
            } catch {
                $rawJson = $null
            }

            $setting | Add-Member -NotePropertyName 'RawJSON' -NotePropertyValue $rawJson -Force -PassThru
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $logMessage = "Failed to retrieve reusable policy settings: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $logMessage -Sev Error -LogData $ErrorMessage
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @{ Results = $logMessage }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Settings)
        })
}
