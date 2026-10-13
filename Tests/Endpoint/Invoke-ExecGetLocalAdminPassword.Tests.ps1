# Pester tests for Invoke-ExecGetLocalAdminPassword.
#
# Thin endpoint over the two LAPS helpers. The part worth pinning is the Platform routing: existing
# callers send no Platform and must keep getting Windows LAPS, macOS must reach the helper keyed on the
# Intune managed device ID, and an unknown Platform must be refused rather than fall through to Windows.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM/Invoke-ExecGetLocalAdminPassword.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecGetLocalAdminPassword.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPLapsPassword { param($Device, $TenantFilter, $APIName, $Headers) }
    function Get-CIPPMacOSLapsPassword { param($Device, $TenantFilter, $APIName, $Headers) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    . $FunctionPath

    function New-LapsRequest {
        param($Platform)
        $Body = [pscustomobject]@{ TenantFilter = 'contoso.com'; guid = 'device-guid' }
        if ($null -ne $Platform) { $Body | Add-Member -NotePropertyName Platform -NotePropertyValue $Platform }
        [pscustomobject]@{
            Body    = $Body
            Query   = [pscustomobject]@{}
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecGetLocalAdminPassword' }
            Headers = @{}
        }
    }
}

Describe 'Invoke-ExecGetLocalAdminPassword' {
    BeforeEach {
        Mock -CommandName Get-CIPPLapsPassword -MockWith { 'windows' }
        Mock -CommandName Get-CIPPMacOSLapsPassword -MockWith { 'macos' }
    }

    It 'retrieves Windows LAPS when no Platform is sent' {
        $Response = Invoke-ExecGetLocalAdminPassword -Request (New-LapsRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be 'windows'
        Should -Invoke Get-CIPPLapsPassword -Times 1 -ParameterFilter { $Device -eq 'device-guid' -and $TenantFilter -eq 'contoso.com' }
        Should -Invoke Get-CIPPMacOSLapsPassword -Times 0
    }

    It 'retrieves macOS LAPS when Platform is macOS' {
        $Response = Invoke-ExecGetLocalAdminPassword -Request (New-LapsRequest -Platform 'macOS') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be 'macos'
        Should -Invoke Get-CIPPMacOSLapsPassword -Times 1 -ParameterFilter { $Device -eq 'device-guid' -and $TenantFilter -eq 'contoso.com' }
        Should -Invoke Get-CIPPLapsPassword -Times 0
    }

    It 'returns 400 for an unknown Platform without calling either helper' {
        $Response = Invoke-ExecGetLocalAdminPassword -Request (New-LapsRequest -Platform 'Linux') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Be 'Invalid Platform specified: Linux.'
        Should -Invoke Get-CIPPLapsPassword -Times 0
        Should -Invoke Get-CIPPMacOSLapsPassword -Times 0
    }

    It 'returns 404 when the device has no macOS LAPS password' {
        Mock -CommandName Get-CIPPMacOSLapsPassword -MockWith { throw [System.Management.Automation.ItemNotFoundException]::new('No macOS LAPS password found for device-guid') }

        $Response = Invoke-ExecGetLocalAdminPassword -Request (New-LapsRequest -Platform 'macOS') -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -Be 'No macOS LAPS password found for device-guid'
    }
}
