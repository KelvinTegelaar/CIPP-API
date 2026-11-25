function Invoke-ManagedBaselinesRequest {
    <#
    .SYNOPSIS
        Calls the CyberDrain Managed Baselines service.
    .DESCRIPTION
        The only function that talks to the service, so an instance that has not enabled the
        integration never calls it. Sends the extension's API key as x-api-key and turns a
        refusal into a message an operator can act on.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('GET', 'POST', 'DELETE')][string]$Method = 'GET',
        $Body
    )

    $Path = $Path.Trim('/')
    if ($Path -notmatch '^[\w/-]+$') {
        throw [System.ArgumentException]::new("'$Path' is not a valid Managed Baselines address.")
    }

    $ConfigTable = Get-CippTable -tablename 'Extensionsconfig'
    $Config = $(try { (Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json -ErrorAction Stop } catch { $null })
    if ($Config.CyberDrainManagedBaselines.Enabled -ne $true) {
        throw [System.ArgumentException]::new('The CyberDrain Managed Baselines integration is not enabled. Enable it under Integrations.')
    }

    $APIKey = Get-ExtensionAPIKey -Extension 'CyberDrainManagedBaselines'
    if ([string]::IsNullOrWhiteSpace($APIKey)) {
        throw [System.ArgumentException]::new('No API key is saved for CyberDrain Managed Baselines. Add it under Integrations.')
    }

    $BaseUrl = 'https://managedbaselines.cipp.app'
    if ($env:CIPP_MANAGED_BASELINES_URL) { $BaseUrl = $env:CIPP_MANAGED_BASELINES_URL.TrimEnd('/') }
    $RestMethod = @{
        Uri     = '{0}/api/{1}' -f $BaseUrl, $Path
        Method  = $Method
        Headers = @{ 'x-api-key' = $APIKey; 'User-Agent' = 'CIPP' }
    }
    if ($null -ne $Body) {
        $RestMethod.Body = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
        $RestMethod.ContentType = 'application/json'
    }

    try {
        Invoke-RestMethod @RestMethod
    } catch {
        switch ([int]$_.Exception.Response.StatusCode.value__) {
            401 { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key. Check the key under Integrations.') }
            402 { throw [System.UnauthorizedAccessException]::new('The Managed Baselines subscription for this API key is not active.') }
            403 { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key. Check the key under Integrations.') }
            404 { throw [System.Management.Automation.ItemNotFoundException]::new('CyberDrain could not find that baseline or request.') }
            429 { throw 'CyberDrain is rate limiting this instance. Try again in a few minutes.' }
            default { throw "The Managed Baselines service could not be reached: $($_.Exception.Message)" }
        }
    }
}
