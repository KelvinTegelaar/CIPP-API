# Pester tests for Invoke-ExecResolveAlert

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecResolveAlert.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecResolveAlert.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    # The Functions host profile provides 'using namespace System.Net'; outside it the
    # bare [HttpStatusCode] the function uses needs a type accelerator.
    $Accelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CippException { param($Exception) }
    function Get-CIPPTable { param($tablename) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant) }

    # Use the real hash and filter-escape helpers so the endpoint's matching and
    # injection hardening stay faithful to production behaviour.
    foreach ($HelperName in @('Get-AlertContentHash.ps1', 'ConvertTo-CIPPODataFilterValue.ps1')) {
        $HelperPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $HelperName -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $HelperPath) { throw "Could not locate $HelperName under Modules/" }
        . $HelperPath
    }

    . $FunctionPath

    function New-ResolveRequest {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecResolveAlert' }
            Headers = @{ Authorization = 'token' }
            Body    = $Body
        }
    }

    function New-AlertRow {
        param($PartitionKey, $Items)
        [pscustomobject]@{
            PartitionKey = $PartitionKey
            RowKey       = 'contoso.com-Get-CIPPAlertMFAAdmins'
            CmdletName   = 'Get-CIPPAlertMFAAdmins'
            Tenant       = 'contoso.com'
            LogData      = (ConvertTo-Json -InputObject @($Items) -Compress -Depth 10 | Out-String)
            AlertComment = ''
        }
    }
}

Describe 'Invoke-ExecResolveAlert' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertLastRun' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = $Exception.Exception.Message } }

        $script:TargetItem = [pscustomobject]@{ UserPrincipalName = 'admin@contoso.com'; Message = 'MFA disabled' }
        $script:OtherItem = [pscustomobject]@{ UserPrincipalName = 'other@contoso.com'; Message = 'MFA disabled' }
        $script:ValidBody = [pscustomobject]@{
            CmdletName   = 'Get-CIPPAlertMFAAdmins'
            TenantFilter = 'contoso.com'
            AlertItem    = $script:TargetItem
        }
    }

    It 'removes the matching item and rewrites the row when other items remain' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-AlertRow -PartitionKey '20260716' -Items @($script:TargetItem, $script:OtherItem)
        }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match '^Resolved alert'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "RowKey eq 'contoso.com-Get-CIPPAlertMFAAdmins'"
        }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.LogData -notmatch 'admin@contoso\.com' -and $Entity.LogData -match 'other@contoso\.com'
        }
        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
    }

    It 'deletes the row entirely when the last item is resolved' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-AlertRow -PartitionKey '20260716' -Items @($script:TargetItem)
        }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-AzDataTableEntity -Times 1 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'removes the item from every partition so older rows cannot resurface it' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            @(
                New-AlertRow -PartitionKey '20260715' -Items @($script:TargetItem)
                New-AlertRow -PartitionKey '20260716' -Items @($script:TargetItem)
            )
        }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-AzDataTableEntity -Times 2 -Exactly
    }

    It 'returns OK with an already-resolved message when no stored item matches' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            New-AlertRow -PartitionKey '20260716' -Items @($script:OtherItem)
        }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body.Results | Should -Match 'already resolved'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
    }

    It 'preserves the LastSeen stamp when rewriting a row' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            $Row = New-AlertRow -PartitionKey '20260716' -Items @($script:TargetItem, $script:OtherItem)
            $Row | Add-Member -NotePropertyName LastSeen -NotePropertyValue '1784216400' -PassThru
        }

        $null = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.LastSeen -eq '1784216400'
        }
    }

    It 'escapes quotes in caller input so the filter cannot be widened' {
        $Body = [pscustomobject]@{
            CmdletName   = 'Get-CIPPAlertMFAAdmins'
            TenantFilter = "x' or RowKey ge '"
            AlertItem    = $script:TargetItem
        }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $Body) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "RowKey eq 'x'' or RowKey ge ''-Get-CIPPAlertMFAAdmins'"
        }
    }

    It 'returns BadRequest when a required field is missing' {
        $Body = [pscustomobject]@{ CmdletName = ''; TenantFilter = 'contoso.com'; AlertItem = $script:TargetItem }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $Body) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $response.Body.Results | Should -Match 'required'
    }

    It 'returns InternalServerError and logs when the table query throws' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { throw 'table unavailable' }

        $response = Invoke-ExecResolveAlert -Request (New-ResolveRequest $script:ValidBody) -TriggerMetadata $null

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $response.Body.Results | Should -Match 'Failed to resolve alert'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }
}
