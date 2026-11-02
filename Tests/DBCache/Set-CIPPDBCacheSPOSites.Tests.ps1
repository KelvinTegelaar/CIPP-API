# The SPOSites collector fans the site URLs out in batches; each batch reads its sites, and
# Push-StoreSPOSites writes once, carrying over the previous row of any site that did not come back.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Triggers = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/SharePoint Sites'

    function Get-CIPPSPOSite { param($TenantFilter, [switch]$UseCertificate, [string[]]$Properties) }
    function Get-CIPPSPOSiteBulk { param($TenantFilter, $SiteUrls, $MaxConcurrency, $BatchSize, $Properties, [switch]$UseCertificate) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Update-CippQueueEntry { param($RowKey, $TotalTasks, [switch]$IncrementTotalTasks) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheSPOSites.ps1')
    . (Join-Path $Triggers 'Push-DBCacheSPOSitesBatch.ps1')
    . (Join-Path $Triggers 'Push-StoreSPOSites.ps1')

    function Get-Url { param($i) "https://contoso.sharepoint.com/sites/s$i" }
    function New-Row { param($i, $Picker = $true) [PSCustomObject]@{ id = "id$i"; Url = (Get-Url $i); Title = "Site $i"; ShowPeoplePickerSuggestionsForGuestUsers = $Picker } }
}

Describe 'Set-CIPPDBCacheSPOSites' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock Start-CIPPOrchestrator {}
    }

    It 'fans the enumerated URLs out in batches of 100 with a capped per-tenant concurrency' {
        Mock Get-CIPPSPOSite { foreach ($i in 1..250) { [PSCustomObject]@{ Url = (Get-Url $i) } } }

        Set-CIPPDBCacheSPOSites -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Get-CIPPSPOSite -Times 1 -Exactly -ParameterFilter { @($Properties) -join ',' -eq 'Url' }
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            $InputObject.Batch.Count -eq 3 -and $InputObject.Batch[2].Urls.Count -eq 50 -and
            $InputObject.MaxConcurrency -gt 0 -and $InputObject.PostExecution.Parameters.TotalBatches -eq 3
        }
    }

    It 'records an authoritative empty set when the tenant has no sites' {
        Mock Get-CIPPSPOSite {}

        Set-CIPPDBCacheSPOSites -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke Start-CIPPOrchestrator -Times 0
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and @($Data).Count -eq 0 }
    }
}

Describe 'Push-DBCacheSPOSitesBatch' {
    It 'returns its URLs and a row only for the sites that answered' {
        Mock Get-CIPPSPOSiteBulk {
            foreach ($Url in $SiteUrls) {
                if ($Url -like '*/s2') { [PSCustomObject]@{ SiteUrl = $Url; Success = $false; Site = $null } }
                else { [PSCustomObject]@{ SiteUrl = $Url; Success = $true; Site = [PSCustomObject]@{ SiteId = 'g'; Title = 'T'; Template = 'GROUP#0'; ShowPeoplePickerSuggestionsForGuestUsers = $true } } }
            }
        }

        $Result = Push-DBCacheSPOSitesBatch -Item ([PSCustomObject]@{ TenantFilter = 'contoso.onmicrosoft.com'; Urls = @((Get-Url 1), (Get-Url 2), (Get-Url 3)) })

        $Result.Urls.Count | Should -Be 3
        @($Result.Sites.Url) | Should -Be @((Get-Url 1), (Get-Url 3))
        $Result.Sites[0].ShowPeoplePickerSuggestionsForGuestUsers | Should -BeTrue
    }
}

Describe 'Push-StoreSPOSites' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        # s3 failed this run, s9 was deleted since the last run
        Mock New-CIPPDbRequest { New-Row 1 $false; New-Row 3 $false; New-Row 9 $false }
    }

    It 'carries over a failed site but lets a deleted site fall out when every batch returned' {
        $Item = @{ Parameters = @{ TenantFilter = 't'; TotalBatches = 2 }; Results = @(
                @{ Urls = @((Get-Url 1), (Get-Url 2)); Sites = @((New-Row 1), (New-Row 2)) }
                @{ Urls = @((Get-Url 3)); Sites = @() }
            )
        }

        Push-StoreSPOSites -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            (@($Data.Url) | Sort-Object) -join ',' -eq ((1, 2, 3 | ForEach-Object { Get-Url $_ }) -join ',') -and
            @($Data | Where-Object Url -EQ (Get-Url 1))[0].ShowPeoplePickerSuggestionsForGuestUsers -eq $true
        }
    }

    It 'keeps every previous row not refreshed when a batch is missing' {
        $Item = @{ Parameters = @{ TenantFilter = 't'; TotalBatches = 2 }; Results = @(@{ Urls = @((Get-Url 1)); Sites = @((New-Row 1)) }) }

        Push-StoreSPOSites -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { @($Data).Count -eq 3 -and @($Data.Url) -contains (Get-Url 9) }
    }

    It 'leaves the cache untouched when no site was read' {
        $Item = @{ Parameters = @{ TenantFilter = 't'; TotalBatches = 1 }; Results = @(@{ Urls = @((Get-Url 1)); Sites = @() }) }

        Push-StoreSPOSites -Item $Item

        Should -Invoke Add-CIPPDbItem -Times 0
    }
}
