# Pester tests for OOO-only offboarding defaults in Invoke-ListUserSettings.
# A non-empty OOO on the user row must win over an all-false allUsers blob.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ListUserSettings.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ListUserSettings.ps1 at $FunctionPath" }
    if (-not (Test-Path $HtmlPath)) { throw "Could not locate Test-CIPPHtmlIsEmpty.ps1 at $HtmlPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-Warning { param($Message) }

    . $HtmlPath
    . $FunctionPath

    function New-ClientPrincipalHeader {
        param([string]$UserDetails = 'admin@partner.com')
        $Json = (@{ userDetails = $UserDetails } | ConvertTo-Json -Compress)
        [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Json))
    }

    function New-SettingsEntity {
        param([string]$RowKey, [hashtable]$OffboardingDefaults)
        $Payload = @{
            direction           = 'ltr'
            offboardingDefaults = $OffboardingDefaults
        }
        [pscustomobject]@{
            PartitionKey = 'UserSettings'
            RowKey       = $RowKey
            JSON         = ($Payload | ConvertTo-Json -Depth 10 -Compress)
        }
    }
}

Describe 'Invoke-ListUserSettings offboarding OOO' {
    BeforeEach {
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = 'UserSettings' } }
        Mock -CommandName Write-Warning -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
    }

    It 'treats user OOO-only defaults as configured when allUsers has no true switches' {
        $AllUsers = New-SettingsEntity -RowKey 'allUsers' -OffboardingDefaults @{
            ConvertToShared = $false
            RemoveGroups    = $false
            OOO             = '<p></p>'
        }
        $UserRow = New-SettingsEntity -RowKey 'admin@partner.com' -OffboardingDefaults @{
            ConvertToShared = $false
            OOO             = '<p>Gone from %tenantname%.</p>'
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -match "RowKey eq 'allUsers'") { return $AllUsers }
            if ($Filter -match "RowKey eq 'admin@partner.com'") { return $UserRow }
            if ($Filter -match "UserBookmarks") { return $null }
            return $null
        }

        $Request = [pscustomobject]@{
            Headers = @{ 'x-ms-client-principal' = (New-ClientPrincipalHeader) }
        }

        $Response = Invoke-ListUserSettings -Request $Request

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.Body.offboardingDefaultsSource | Should -Be 'user'
        $Response.Body.offboardingDefaults.OOO | Should -Be '<p>Gone from %tenantname%.</p>'
    }

    It 'does not treat empty TipTap OOO alone as configured on the user row' {
        $AllUsers = New-SettingsEntity -RowKey 'allUsers' -OffboardingDefaults @{
            ConvertToShared = $false
            OOO             = ''
        }
        $UserRow = New-SettingsEntity -RowKey 'admin@partner.com' -OffboardingDefaults @{
            ConvertToShared = $false
            OOO             = '<p><br></p>'
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Context, $Filter)
            if ($Filter -match "RowKey eq 'allUsers'") { return $AllUsers }
            if ($Filter -match "RowKey eq 'admin@partner.com'") { return $UserRow }
            if ($Filter -match "UserBookmarks") { return $null }
            return $null
        }

        $Response = Invoke-ListUserSettings -Request ([pscustomobject]@{
                Headers = @{ 'x-ms-client-principal' = (New-ClientPrincipalHeader) }
            })

        $Response.Body.offboardingDefaultsSource | Should -Be 'allUsers'
    }
}
