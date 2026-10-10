# A synced baseline saved with no GitHub block is a local edit not yet pushed - flag it true.
# A save with a GitHub block that pushes successfully clears the flag (via Push-CIPPBaselineToRepo's
# own rollout stamp); a failed push must leave it true, so AddBaseline never writes false itself.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-AddBaseline.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPTable { param($TableName) @{ Context = "stub-$TableName" } }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    # Untyped (unlike the real [bool] param) so $LocalChanges is $null when the caller
    # didn't pass -LocalChanges at all, distinguishing "not passed" from "passed $false".
    function New-CIPPBaseline { param($Baseline, $User, $Source, $SHA, $SourcePath, $LocalChanges) }
    function Push-CIPPBaselineToRepo { param($GUID, $FullName, $Message) }

    . $FunctionPath

    function New-Request {
        param($Guid, $GitHub)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
        $BodyProps = [ordered]@{
            GUID         = $Guid
            templateName = 'My Baseline'
            stages       = @([pscustomobject]@{ name = 'Stage 1'; standards = @() })
        }
        if ($GitHub) { $BodyProps['GitHub'] = $GitHub }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddBaseline' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]$BodyProps
        }
    }
}

Describe 'Invoke-AddBaseline LocalChanges' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-CIPPBaseline -MockWith { @{ GUID = 'baseline-1'; DeltaCount = 0 } }
    }

    It 'passes -LocalChanges:$true on a plain save of a synced baseline (no GitHub block)' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'baseline-1'; Source = 'Org/repo'; SHA = 'abc123' }
        }
        $null = Invoke-AddBaseline -Request (New-Request -Guid 'baseline-1')
        Should -Invoke New-CIPPBaseline -Times 1 -ParameterFilter { $LocalChanges -eq $true }
    }

    It 'does not pass -LocalChanges for a baseline that was never synced' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        $null = Invoke-AddBaseline -Request (New-Request -Guid 'baseline-2')
        Should -Invoke New-CIPPBaseline -Times 1 -ParameterFilter { $null -eq $LocalChanges }
    }

    It 'does not pass -LocalChanges when a GitHub block is sent, and pushes after the save' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'baseline-1'; Source = 'Org/repo'; SHA = 'abc123' }
        }
        Mock -CommandName Push-CIPPBaselineToRepo -MockWith { @{ resultText = 'ok'; state = 'success' } }

        $Response = Invoke-AddBaseline -Request (New-Request -Guid 'baseline-1' -GitHub ([pscustomobject]@{ FullName = 'Org/repo'; Message = 'push it' }))

        Should -Invoke New-CIPPBaseline -Times 1 -ParameterFilter { $null -eq $LocalChanges }
        Should -Invoke Push-CIPPBaselineToRepo -Times 1 -ParameterFilter { $GUID -eq 'baseline-1' -and $FullName -eq 'Org/repo' }
        $Response.Body.Results | Should -BeLike '*Pushed to Org/repo*'
    }

    It 'leaves the flag alone (no explicit write) when the push fails' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'baseline-1'; Source = 'Org/repo'; SHA = 'abc123' }
        }
        Mock -CommandName Push-CIPPBaselineToRepo -MockWith { @{ resultText = 'boom'; state = 'error' } }

        $Response = Invoke-AddBaseline -Request (New-Request -Guid 'baseline-1' -GitHub ([pscustomobject]@{ FullName = 'Org/repo'; Message = 'push it' }))

        Should -Invoke New-CIPPBaseline -Times 1 -ParameterFilter { $null -eq $LocalChanges }
        $Response.Body.Results | Should -BeLike '*Failed to push*'
    }
}
