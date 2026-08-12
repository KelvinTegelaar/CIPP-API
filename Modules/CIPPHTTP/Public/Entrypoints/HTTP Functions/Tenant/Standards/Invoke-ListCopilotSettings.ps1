function Invoke-ListCopilotSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Lists the Microsoft 365 Copilot admin policy settings for a tenant, one row per setting,
        with the current raw value and a friendly state (Enabled / Disabled / Not configured).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    $PolicySettings = @(
        @{ setting = 'Pin Microsoft 365 Copilot Chat'; id = 'microsoft.copilot.copilotchatpinning' }
        @{ setting = 'Block Copilot Access to Open Content'; id = 'microsoft.copilot.blockaccesstoopenfiles' }
        @{ setting = 'Designer Image Generation'; id = 'microsoft.copilot.imagegeneration' }
        @{ setting = 'Allow web search in Copilot'; id = 'microsoft.copilot.allowwebsearch' }
        @{ setting = 'Admin Copilot in Microsoft 365 Admin Center'; id = 'microsoft.copilot.allowinadmincenters' }
    )

    # One $batch call instead of five sequential GETs. The Copilot admin APIs currently require
    # delegated auth (no -AsApp). Reading each item's body directly also sidesteps the single-request
    # helper's collection unwrapping of the entity's scalar 'value' property.
    $BulkRequests = foreach ($Setting in $PolicySettings) {
        @{
            id     = $Setting.id
            method = 'GET'
            url    = "/copilot/admin/policySettings/$($Setting.id)"
        }
    }

    try {
        $BulkResults = New-GraphBulkRequest -Requests @($BulkRequests) -tenantid $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CopilotSettings' -tenant $TenantFilter -message "Could not read Copilot settings. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $BulkResults = @()
    }

    # Web search is a three-state setting. The values are the config.office.com policy options in
    # order, zero-indexed: 0 is the first (most permissive) option, 2 the last. Verified against a
    # tenant holding '0', which the Microsoft 365 Apps admin center reports as fully enabled.
    $WebSearchStates = @{
        '0' = 'Enabled in Copilot and Copilot Chat'
        '1' = 'Disabled in Copilot and Copilot Chat'
        '2' = 'Disabled in Copilot Work mode, Enabled in Copilot Chat'
    }

    # Designer image generation inverts the usual toggle: '1' disables it, '0' enables it.
    $InvertedToggleSettings = @('microsoft.copilot.imagegeneration')

    # 'Block Copilot Access to Open Content' is phrased as a block, so plain Enabled/Disabled reads
    # ambiguously. Use the same wording as the standard's own option list.
    $BlockToggleStates = @{
        '1' = 'Blocked'
        '0' = 'Allowed'
    }

    $Results = foreach ($Setting in $PolicySettings) {
        $Response = $BulkResults | Where-Object { $_.id -eq $Setting.id }
        $Value = $null
        if ($Response.status -ge 200 -and $Response.status -le 299) {
            $Value = $Response.body.value
            $StateText = if ([string]::IsNullOrEmpty($Value)) {
                'Not configured'
            } elseif ($Setting.id -eq 'microsoft.copilot.allowwebsearch' -and $WebSearchStates[[string]$Value]) {
                $WebSearchStates[[string]$Value]
            } elseif ($Setting.id -eq 'microsoft.copilot.blockaccesstoopenfiles' -and $BlockToggleStates[[string]$Value]) {
                $BlockToggleStates[[string]$Value]
            } elseif ($Value -eq '1') {
                if ($Setting.id -in $InvertedToggleSettings) { 'Disabled' } else { 'Enabled' }
            } elseif ($Value -eq '0') {
                if ($Setting.id -in $InvertedToggleSettings) { 'Enabled' } else { 'Disabled' }
            } else {
                "Custom ($Value)"
            }
        } else {
            Write-LogMessage -API 'CopilotSettings' -tenant $TenantFilter -message "Could not read Copilot setting $($Setting.id). Error: $($Response.body.error.message ?? 'No response')" -Sev 'Error'
            $StateText = 'Unable to read'
        }
        [PSCustomObject]@{
            setting   = $Setting.setting
            state     = $StateText
            value     = $Value
            settingId = $Setting.id
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}
