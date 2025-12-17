function Update-CIPPAzFunctionAppSetting {
    <#
    .SYNOPSIS
        Updates Azure Function App application settings via ARM REST using managed identity.
    .PARAMETER Name
        Function App name.
    .PARAMETER ResourceGroupName
        Resource group name.
    .PARAMETER AppSetting
        Hashtable of settings to set (key/value). Values should be strings.
    .PARAMETER RemoveKeys
        Optional array of setting keys to remove from the Function App configuration. Removals are applied after merging updates and before PUT.
    .PARAMETER AccessToken
        Optional bearer token to override Managed Identity. If provided, this token is used for Authorization.
    .EXAMPLE
        Update-CIPPAzFunctionAppSetting -Name myfunc -ResourceGroupName rg1 -AppSetting @{ WEBSITE_TIME_ZONE = 'UTC' }
    .EXAMPLE
        Update-CIPPAzFunctionAppSetting -Name myfunc -ResourceGroupName rg1 -AppSetting @{ WEBSITE_TIME_ZONE = 'UTC' } -RemoveKeys @('OLD_KEY','LEGACY_SETTING')
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $true)]
        [hashtable]$AppSetting,

        [Parameter(Mandatory = $false)]
        [string[]]$RemoveKeys,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken
    )

    # Build ARM URIs
    $subscriptionId = Get-CIPPAzFunctionAppSubId
    $apiVersion = '2024-11-01'
    $updateUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$Name/config/appsettings?api-version=$apiVersion"

    # Fetch current settings to avoid overwriting unrelated keys
    $current = $null
    try {
        # Prefer the dedicated getter to handle ARM quirks
        $GetSettings = @{
            Name              = $Name
            ResourceGroupName = $ResourceGroupName
        }
        if ($AccessToken) { $GetSettings.AccessToken = $AccessToken }
        $current = Get-CIPPAzFunctionAppSetting @GetSettings
    } catch { $current = $null }
    $currentProps = @{}
    if ($current -and $current.properties) {
        # Handle PSCustomObject properties (JSON deserialization result)
        if ($current.properties -is [hashtable]) {
            foreach ($ck in $current.properties.Keys) { $currentProps[$ck] = [string]$current.properties[$ck] }
        } else {
            # PSCustomObject - enumerate using PSObject.Properties
            foreach ($prop in $current.properties.PSObject.Properties) {
                $currentProps[$prop.Name] = [string]$prop.Value
            }
        }
    }

    # Merge requested settings
    foreach ($k in $AppSetting.Keys) { $currentProps[$k] = [string]$AppSetting[$k] }

    # Apply removals if specified
    if ($RemoveKeys -and $RemoveKeys.Count -gt 0) {
        foreach ($rk in $RemoveKeys) {
            if ($currentProps.ContainsKey($rk)) {
                [void]$currentProps.Remove($rk)
            }
        }
    }
    $body = @{ properties = $currentProps }

    if ($PSCmdlet.ShouldProcess($Name, 'Update Function App settings')) {
        $restParams = @{ Uri = $updateUri; Method = 'PUT'; Body = $body; ContentType = 'application/json' }
        if ($AccessToken) { $restParams.AccessToken = $AccessToken }
        $resp = New-CIPPAzRestRequest @restParams
        return $resp
    }
}
