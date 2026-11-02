# Pester tests for Invoke-ExecClrOnPremAttributes.
#
# Thin endpoint over Clear-CIPPOnPremisesAttributes. The part worth pinning is the Attributes parsing:
# the frontend autoComplete sends {label,value} objects, API scripts send plain strings, and a missing
# list must reach the helper empty so it clears every documented on-premises attribute.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecClrOnPremAttributes.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-ExecClrOnPremAttributes.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Clear-CIPPOnPremisesAttributes { param($UserID, $TenantFilter, $Headers, $APIName, $Attributes) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-ClrRequest {
        param($Attributes)
        $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; ID = 'user-guid' }
        if ($null -ne $Attributes) { $Body | Add-Member -NotePropertyName Attributes -NotePropertyValue $Attributes }
        [pscustomobject]@{
            Body    = $Body
            Query   = [pscustomobject]@{}
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecClrOnPremAttributes' }
            Headers = @{}
        }
    }
}

Describe 'Invoke-ExecClrOnPremAttributes' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        $script:Captured = $null
        Mock -CommandName Clear-CIPPOnPremisesAttributes -MockWith { $script:Captured = @($Attributes); 'ok' }
    }

    It 'unwraps autoComplete objects to attribute names' {
        $Selected = @(
            [pscustomobject]@{ label = 'Immutable ID'; value = 'onPremisesImmutableId' },
            [pscustomobject]@{ label = 'SAM'; value = 'onPremisesSamAccountName' }
        )

        $Response = Invoke-ExecClrOnPremAttributes -Request (New-ClrRequest -Attributes $Selected) -TriggerMetadata $null

        $script:Captured | Should -Be @('onPremisesImmutableId', 'onPremisesSamAccountName')
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be 'ok'
        Should -Invoke Clear-CIPPOnPremisesAttributes -Times 1 -ParameterFilter { $UserID -eq 'user-guid' -and $TenantFilter -eq 'contoso.com' }
    }

    It 'accepts plain attribute names' {
        Invoke-ExecClrOnPremAttributes -Request (New-ClrRequest -Attributes @('onPremisesDomainName')) -TriggerMetadata $null

        $script:Captured | Should -Be @('onPremisesDomainName')
    }

    It 'passes an empty list through when no attributes are sent' {
        Invoke-ExecClrOnPremAttributes -Request (New-ClrRequest) -TriggerMetadata $null

        $script:Captured.Count | Should -Be 0
    }

    It 'returns 500 with the helper error message' {
        Mock -CommandName Clear-CIPPOnPremisesAttributes -MockWith { throw 'graph said no' }

        $Response = Invoke-ExecClrOnPremAttributes -Request (New-ClrRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Be 'graph said no'
    }
}
