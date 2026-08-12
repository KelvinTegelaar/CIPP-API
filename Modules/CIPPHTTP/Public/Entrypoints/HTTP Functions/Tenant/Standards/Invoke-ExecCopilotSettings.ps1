function Invoke-ExecCopilotSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.ReadWrite
    .DESCRIPTION
        Sets a single Microsoft 365 Copilot policy setting to Enabled (1), Disabled (0) or Not configured (cleared).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    $SettingId = $Request.Body.settingId.value ?? $Request.Body.settingId
    $Value = $Request.Body.value.value ?? $Request.Body.value

    $AllowedSettings = @(
        'microsoft.copilot.copilotchatpinning'
        'microsoft.copilot.blockaccesstoopenfiles'
        'microsoft.copilot.imagegeneration'
        'microsoft.copilot.allowwebsearch'
        'microsoft.copilot.allowinadmincenters'
    )

    if ($SettingId -notin $AllowedSettings) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [pscustomobject]@{ Results = "Unsupported Copilot setting: $SettingId" }
            })
    }

    # Web search is three-state (0 = enabled everywhere, 1 = disabled everywhere, 2 = disabled in
    # Copilot Work mode only), and image generation inverts the usual toggle ('1' disables it).
    # These are only used for the log line - the value is passed through to Graph either way.
    $WebSearchStates = @{
        '0' = 'Enabled in Copilot and Copilot Chat'
        '1' = 'Disabled in Copilot and Copilot Chat'
        '2' = 'Disabled in Copilot Work mode, Enabled in Copilot Chat'
    }
    $InvertedToggleSettings = @('microsoft.copilot.imagegeneration')

    # 'clear'/'notconfigured'/blank -> remove the value (Not configured); otherwise set the string value.
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -in @('clear', 'notconfigured')) {
        $PatchBody = [pscustomobject]@{ value = $null } | ConvertTo-Json -Compress
        $StateText = 'Not configured'
    } else {
        $PatchBody = [pscustomobject]@{ value = [string]$Value } | ConvertTo-Json -Compress
        $StateText = if ($SettingId -eq 'microsoft.copilot.allowwebsearch' -and $WebSearchStates[[string]$Value]) {
            $WebSearchStates[[string]$Value]
        } elseif ($Value -eq '1') {
            if ($SettingId -in $InvertedToggleSettings) { 'Disabled' } else { 'Enabled' }
        } elseif ($Value -eq '0') {
            if ($SettingId -in $InvertedToggleSettings) { 'Enabled' } else { 'Disabled' }
        } else {
            "value '$Value'"
        }
    }

    # The Copilot admin APIs currently require delegated auth, so use the default delegated token.
    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/copilot/admin/policySettings/$SettingId" -tenantid $TenantFilter -type PATCH -body $PatchBody -ContentType 'application/json'
        $Results = "Set '$SettingId' to $StateText"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to set '$SettingId' to ${StateText}: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::OK
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ Results = $Results }
        })
}
