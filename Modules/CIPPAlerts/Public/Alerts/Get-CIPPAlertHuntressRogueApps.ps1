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
        $RogueApps = Invoke-RestMethod -Uri 'https://huntresslabs.github.io/rogueapps/rogueapps.json'
        $CippRogueApps = (Get-Content -Path (Join-Path $env:CIPPRootPath 'Config\schemaDefinitions.json') | ConvertFrom-Json).applications.appId
        $HuntressRogueApps = $RogueApps.appId
        $RogueAppIds = @($CippRogueApps) + @($HuntressRogueApps) | Where-Object { $_ } | Select-Object -Unique
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
                $RogueApp = $RogueApps | Where-Object { $_.appId -eq $ServicePrincipal.appId }
                [pscustomobject]@{
                    'App Name'       = $RogueApp.appDisplayName
                    'App Id'         = $RogueApp.appId
                    'Description'    = $RogueApp.description
                    'Enabled'        = $ServicePrincipal.accountEnabled
                    'Created'        = $ServicePrincipal.createdDateTime
                    'Tags'           = $RogueApp.tags -join ', '
                    'References'     = $RogueApp.references -join ', '
                    'Huntress Added' = $RogueApp.dateAdded
                }
            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        #$ErrorMessage = Get-CippException -Exception $_
        #Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check for rogue apps for $($TenantFilter): $($ErrorMessage.NormalizedError)"
    }
}
