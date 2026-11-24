# Pester tests for the app package storage reads: Invoke-ListAppPackageStorage (space used and limit) and the
# per-template package size in Invoke-ListAppTemplates.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-CIPPAppPackageStorage { }
    function Get-CIPPAppPackageFile { [CmdletBinding()] param() }
    foreach ($Name in 'Invoke-ListAppPackageStorage', 'Invoke-ListAppTemplates') {
        $Path = Join-Path $RepoRoot "Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/$Name.ps1"
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Path -Raw)))
    }
    function New-Request { [pscustomobject]@{ Query = @{}; Body = $null; Headers = @{}; Params = @{} } }
    $script:PackageA = '6f1c2a3b-1111-2222-3333-444455556666'
    $script:PackageB = '7f1c2a3b-1111-2222-3333-444455556666'
    function New-File { param($PackageId, $File, $Size, [switch]$Custom) [pscustomobject]@{ PackageId = $PackageId; Name = "$PackageId/$File"; Size = [int64]$Size; Custom = [bool]$Custom } }
}

Describe 'Invoke-ListAppPackageStorage' {
    It 'reports CIPP storage against its limit, and a connected account separately' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'theirs'; Custom = $true; AccountName = 'mine'; LimitBytes = 0 } }
        Mock Get-CIPPAppPackageFile { New-File $script:PackageA 'IntunePackage.intunewin' 3GB; New-File $script:PackageA 'metadata.json' 512; New-File $script:PackageB 'IntunePackage.intunewin' 1GB -Custom }

        $Response = Invoke-ListAppPackageStorage -Request (New-Request) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        @($Response.Body).Count | Should -Be 1
        $Usage = @($Response.Body)[0]
        $Usage.UsedBytes | Should -Be (3GB + 512)
        $Usage.AccountBytes | Should -Be 1GB
        $Usage.AccountName | Should -Be 'mine'
        $Usage.LimitBytes | Should -Be 0
    }

    It 'reports nothing used before the first upload, with the hosted limit' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'own'; Custom = $false; AccountName = $null; LimitBytes = 10GB } }
        Mock Get-CIPPAppPackageFile { }

        $Usage = @((Invoke-ListAppPackageStorage -Request (New-Request) -TriggerMetadata $null).Body)[0]

        $Usage.UsedBytes | Should -Be 0
        $Usage.AccountBytes | Should -Be 0
        $Usage.LimitBytes | Should -Be 10GB
    }

    It 'fails when a storage account cannot be listed' {
        Mock Get-CIPPAppPackageStorage { [pscustomobject]@{ ConnectionString = 'theirs'; Custom = $true; AccountName = 'mine'; LimitBytes = 0 } }
        Mock Get-CIPPAppPackageFile { Write-Error 'Status 403 AuthorizationFailure' }

        (Invoke-ListAppPackageStorage -Request (New-Request) -TriggerMetadata $null).StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
    }
}

Describe 'Invoke-ListAppTemplates package size' {
    BeforeEach {
        Mock Get-CIPPAppPackageFile { New-File $script:PackageA 'IntunePackage.intunewin' 100MB; New-File $script:PackageA 'metadata.json' 512; New-File $script:PackageB 'IntunePackage.intunewin' 50MB -Custom }
        # Each app's config is stored as a JSON string inside the template JSON
        $Config = { param($Id) ConvertTo-Json -Compress @{ packageId = $Id } }
        $Packaged = ConvertTo-Json -Depth 5 -Compress @{ Displayname = 'Packaged'; Apps = @(@{ appName = 'A'; appType = 'win32PackageApp'; config = (& $Config $script:PackageA) }, @{ appName = 'B'; appType = 'macOSPackageApp'; config = (& $Config $script:PackageB) }) }
        $Store = ConvertTo-Json -Depth 5 -Compress @{ Displayname = 'Store'; Apps = @(@{ appName = 'C'; appType = 'StoreApp'; config = '{}' }) }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ RowKey = '1'; JSON = $Packaged }; [pscustomobject]@{ RowKey = '2'; JSON = $Store } }
    }

    It 'adds up the packages a template uses wherever they are stored, and leaves templates without packages empty' {
        $Templates = (Invoke-ListAppTemplates -Request (New-Request) -TriggerMetadata $null).Body | ConvertFrom-Json

        $Templates.Where({ $_.displayName -eq 'Packaged' })[0].packageSizeInBytes | Should -Be 150MB
        $Templates.Where({ $_.displayName -eq 'Store' })[0].packageSizeInBytes | Should -BeNullOrEmpty
    }

    It 'still lists templates when package storage cannot be read' {
        Mock Get-CIPPAppPackageFile { throw 'key vault unavailable' }

        $Templates = (Invoke-ListAppTemplates -Request (New-Request) -TriggerMetadata $null).Body | ConvertFrom-Json

        $Templates.Count | Should -Be 2
    }
}
