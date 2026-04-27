function Invoke-ListIntuneReusableSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $SettingId = $Request.Query.ID

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body = @{ Results = 'tenantFilter is required' }
        })
    }

    try {
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
