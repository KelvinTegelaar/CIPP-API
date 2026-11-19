# Issue #1323: SharePoint ignores File Requests writes below 'Anyone' sharing, so the baseline reported Remediated forever.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Invoke-CIPPBaselineSPOTenant { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineSPFileRequests.ps1')

    function New-Spec {
        param($State)
        [PSCustomObject]@{ properties = [PSCustomObject]@{ CoreRequestFilesLinkEnabled = $State; OneDriveRequestFilesLinkEnabled = $State } }
    }
    # The SPOTenant cache row round-trips through JSON, so SharingCapability arrives as Int64.
    function New-Cached {
        param([int64]$SharingCapability)
        [PSCustomObject]@{ SharingCapability = $SharingCapability; CoreRequestFilesLinkEnabled = $false }
    }
}

Describe 'Invoke-CIPPBaselineSPFileRequests' {
    BeforeEach {
        Mock Invoke-CIPPBaselineSPOTenant { }
    }

    It 'refuses to enable File Requests below Anyone sharing, naming the level, and writes nothing' {
        { Invoke-CIPPBaselineSPFileRequests -Remediate (New-Spec $true) -TenantFilter 'contoso.com' -Current (New-Cached 1) } | Should -Throw "*'External Users Only'*"
        Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 0
    }

    It 'enables File Requests through the SPOTenant executor at Anyone sharing' {
        $Spec = New-Spec $true
        $Cached = New-Cached 2

        Invoke-CIPPBaselineSPFileRequests -Remediate $Spec -TenantFilter 'contoso.com' -Current $Cached

        Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly -ParameterFilter { $Remediate -eq $Spec -and $TenantFilter -eq 'contoso.com' -and $Current -eq $Cached }
    }

    It 'disables File Requests at any sharing level' {
        Invoke-CIPPBaselineSPFileRequests -Remediate (New-Spec $false) -TenantFilter 'contoso.com' -Current (New-Cached 0)

        Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly
    }

    It 'does not refuse when the cache has no sharing level to judge by' {
        Invoke-CIPPBaselineSPFileRequests -Remediate (New-Spec $true) -TenantFilter 'contoso.com' -Current $null

        Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly
    }
}
