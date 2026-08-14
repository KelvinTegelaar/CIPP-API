function Get-CIPPAlertHuntressRogueApps {
    <#
    .SYNOPSIS
        Check for rogue apps in a Tenant
    .DESCRIPTION
        This function checks for rogue apps in the tenant by comparing the service principals in the tenant with a list of known rogue apps provided by Huntress and a CIPP collections of appids.
    .FUNCTIONALITY
        Entrypoint
    .LINK
        https://huntresslabs.github.io/rogueapps/
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        # Skip the run rather than alert if the feed is down. A GitHub Pages error page parses
        # without throwing, so the shape is checked too - otherwise this silently degrades to
        # comparing against the CIPP list alone.
        $RogueApps = Invoke-RestMethod -Uri 'https://huntresslabs.github.io/rogueapps/rogueapps.json'
        if (-not @($RogueApps).Where({ $_.appId }, 'First')) { return }

        $CippApps = @((Get-Content -Path (Join-Path $env:CIPPRootPath 'Config\MaliciousApps.json') | ConvertFrom-Json).applications)
        $CippRogueApps = $CippApps.appId
        $HuntressRogueApps = $RogueApps.appId
        $RogueAppIds = @($CippRogueApps) + @($HuntressRogueApps) | Where-Object { $_ } | Select-Object -Unique

        # Describe a match from whichever list it came from. Most of the CIPP entries are not in
        # the Huntress feed, and looking those up there alone left every field blank.
        $AppDetails = @{}
        foreach ($App in @($RogueApps)) {
            if ($App.appId) {
                $AppDetails[[string]$App.appId] = [pscustomobject]@{
                    Name = $App.appDisplayName; Description = $App.description
                    Tags = $App.tags; References = $App.references; Added = $App.dateAdded; Source = 'Huntress'
                }
            }
        }
        foreach ($App in $CippApps) {
            if ($App.appId -and -not $AppDetails.ContainsKey([string]$App.appId)) {
                $AppDetails[[string]$App.appId] = [pscustomobject]@{
                    Name = $App.name; Description = $App.description
                    Tags = $App.tags; References = $App.references; Added = $null; Source = 'CIPP'
                }
            }
        }
        $Requests = for ($i = 0; $i -lt $RogueAppIds.Count; $i += 15) {
            $Chunk = $RogueAppIds[$i..([Math]::Min($i + 14, $RogueAppIds.Count - 1))]
            @{
                id     = [string]$i
                method = 'GET'
                url    = "servicePrincipals?`$filter=appId in ('$($Chunk -join "','")')"
            }
        }
        $Requests = @($Requests)

        $ServicePrincipals = if ($Requests.Count -gt 0) {
            $Responses = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter
            foreach ($Response in $Responses) { $Response.body.value }
        }
        # If IgnoreDisabledApps is true, filter out disabled service principals
        if ($InputValue -eq $true) {
            $ServicePrincipals = $ServicePrincipals | Where-Object { $_.accountEnabled -eq $true }
        }

        if (($ServicePrincipals | Measure-Object).Count -gt 0) {
            $AlertData = foreach ($ServicePrincipal in $ServicePrincipals) {
                $RogueApp = $AppDetails[[string]$ServicePrincipal.appId]
                [pscustomobject]@{
                    # Fall back to the service principal for the identity fields so a row is never
                    # anonymous, even if a list entry is missing.
                    'App Name'    = $RogueApp.Name ?? $ServicePrincipal.appDisplayName
                    'App Id'      = $ServicePrincipal.appId
                    'Description' = $RogueApp.Description
                    'Enabled'     = $ServicePrincipal.accountEnabled
                    'Created'     = $ServicePrincipal.createdDateTime
                    'Tags'        = $RogueApp.Tags -join ', '
                    'References'  = $RogueApp.References -join ', '
                    'Source'      = $RogueApp.Source
                    'Listed On'   = $RogueApp.Added
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        #$ErrorMessage = Get-CippException -Exception $_
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check for rogue apps for $($TenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
