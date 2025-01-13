function Start-CIPPStatsTimer {
    <#
    .SYNOPSIS
    Start the CIPP Stats Timer
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    #These stats are sent to a central server to help us understand how many tenants are using the product, and how many are using the latest version, this information allows the CIPP team to make decisions about what features to support, and what features to deprecate.
    #We will never ship any data that is related to your instance, all we care about is the number of tenants, and the version of the API you are running, and if you completed setup.

    if ($PSCmdlet.ShouldProcess('Start-CIPPStatsTimer', 'Starting CIPP Stats Timer')) {
        if ($ENV:ApplicationID -ne 'LongApplicationID') {
            $SetupComplete = $true
        }
        $TenantCount = (Get-Tenants -IncludeAll).count


        $ModuleBase = Get-Module CIPPCore | Select-Object -ExpandProperty ModuleBase
        $CIPPRoot = (Get-Item $ModuleBase).Parent.Parent.FullName

        $APIVersion = Get-Content "$CIPPRoot\version_latest.txt" | Out-String

        $SendingObject = [PSCustomObject]@{
            rgid                = $env:WEBSITE_SITE_NAME
            SetupComplete       = $SetupComplete
            RunningVersionAPI   = $APIVersion.trim()
            CountOfTotalTenants = $tenantcount
            uid                 = $env:TenantID
        } | ConvertTo-Json

        Invoke-RestMethod -Uri 'https://management.cipp.app/api/stats' -Method POST -Body $SendingObject -ContentType 'application/json'
    }
}
