# The SAM manifest timestamp: a rebuild with unchanged content must not move it
# (mtime restamps re-queued the whole estate for CPV); a real change must.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CippSamPermissions.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Get-CippSamPermissions.ps1 under Modules/' }

    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Get-CippAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($Uri, $tenantid, $NoAuthCheck, $AsApp) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $NoAuthCheck, $asapp) }
    function Write-LogMessage { param($message, $tenant, $API, $sev, $Headers, $LogData) }

    . $FunctionPath

    $script:ConfigRoot = Join-Path ([IO.Path]::GetTempPath()) ("samman-" + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path (Join-Path $script:ConfigRoot 'Config') -Force
    $script:ManifestPath = Join-Path $script:ConfigRoot 'Config/SAMManifest.json'
    $script:AdditionalPath = Join-Path $script:ConfigRoot 'Config/AdditionalPermissions.json'
    $env:CIPPRootPath = $script:ConfigRoot
    $env:TenantID = '00000000-0000-0000-0000-000000000001'

    function Set-Manifest {
        param([string]$Scope = 'Directory.Read.All')
        @{ requiredResourceAccess = @(@{ resourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = @(@{ id = '11111111-1111-1111-1111-111111111111'; type = 'Scope'; value = $Scope }) }) } |
            ConvertTo-Json -Depth 10 | Set-Content -Path $script:ManifestPath
        '[]' | Set-Content -Path $script:AdditionalPath
    }
    Set-Manifest
}

AfterAll {
    Remove-Item -Path $script:ConfigRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Get-CippSamPermissions manifest timestamp' {
    BeforeEach {
        $script:HashRow = $null
        $script:Written = [System.Collections.Generic.List[object]]::new()
        # Clear the 5-minute -NoDiff memo between calls.
        $script:CippSamPermissionsCache = $null
        $script:CippSamPermissionsCacheTime = $null

        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName Get-CippAzDataTableEntity -MockWith {
            if ($Filter -match 'ManifestHash') { return $script:HashRow }
            return $null   # no saved extra permissions
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            $script:Written.Add($Entity)
            $script:HashRow = [pscustomobject]$Entity
        }
    }

    It 'records the hash the first time it sees a permission set' {
        $null = Get-CippSamPermissions -NoDiff

        $script:Written.Count | Should -Be 1
        $script:Written[0].RowKey | Should -Be 'ManifestHash'
        $script:Written[0].Hash | Should -Not -BeNullOrEmpty
    }

    It 'does not move the timestamp when only the file mtime changes' {
        # Exactly what a checkout or container rebuild does: same bytes, new mtime.
        $first = (Get-CippSamPermissions -NoDiff).Timestamp
        (Get-Item $script:ManifestPath).LastWriteTime = [datetime]::Now.AddDays(1)
        $script:CippSamPermissionsCache = $null; $script:CippSamPermissionsCacheTime = $null
        $second = (Get-CippSamPermissions -NoDiff).Timestamp

        $second | Should -Be $first
        $script:Written.Count | Should -Be 1   # nothing re-recorded
    }

    It 'moves the timestamp when the permission set actually changes' {
        $first = (Get-CippSamPermissions -NoDiff).Timestamp
        Start-Sleep -Milliseconds 1100         # the stamp has second resolution
        Set-Manifest -Scope 'Directory.ReadWrite.All'
        $script:CippSamPermissionsCache = $null; $script:CippSamPermissionsCacheTime = $null
        $second = (Get-CippSamPermissions -NoDiff).Timestamp

        $second | Should -BeGreaterThan $first
        $script:Written.Count | Should -Be 2
    }

    It 'falls back to the mtime if the hash cannot be persisted' {
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { throw 'table unavailable' }
        $mtime = [datetime]::Now.AddDays(-3)
        (Get-Item $script:ManifestPath).LastWriteTime = $mtime

        $result = Get-CippSamPermissions -NoDiff

        ([datetime]$result.Timestamp).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') |
            Should -Be $mtime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
