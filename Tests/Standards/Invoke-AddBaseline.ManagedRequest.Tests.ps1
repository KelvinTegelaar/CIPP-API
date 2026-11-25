# Saving the baseline CyberDrain delivered for a custom request: the editor's first save carries
# the request id and the version it loaded. That save goes through the request, not a plain write,
# and neither value is stored on the baseline.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CIPPTable { param($TableName) @{ Context = "stub-$TableName" } }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GitHub/Test-CIPPRepoSource.ps1')
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function New-CIPPBaseline { param($Baseline, $User, $Source, $SHA, $SourcePath, $LocalChanges) }
    function Push-CIPPBaselineToRepo { param($GUID, $FullName, $Message) }
    function Get-CIPPBaseline { param($ID) }
    function Get-CIPPBaselineOutOfScopeAssignment { param($Assignments) }
    function Complete-CIPPManagedBaselineRequest { param($RequestId, $Baseline, $Version, $User) }
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-AddBaseline.ps1')

    function New-Request {
        param($Guid, $ManagedRequestId = 'request-9')
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@partner.example"}'))
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddBaseline' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject][ordered]@{
                GUID             = $Guid
                templateName     = 'Contoso baseline'
                assignedTenants  = @([pscustomobject]@{ value = 'contoso.com'; label = 'Contoso'; type = 'Tenant' })
                stages           = @([pscustomobject]@{ name = 'Baseline'; standards = @() })
                managedRequestId = $ManagedRequestId
                managedVersion   = '2'
            }
        }
    }
}

Describe 'Invoke-AddBaseline with a delivered custom baseline' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPBaselineOutOfScopeAssignment {}
        Mock New-CIPPBaseline { @{ GUID = 'plain-save'; DeltaCount = 0 } }
        Mock Complete-CIPPManagedBaselineRequest { @{ GUID = 'baseline-1'; DeltaCount = 4 } }
    }

    It 'saves through the request, with the version the editor loaded' {
        $Response = Invoke-AddBaseline -Request (New-Request)

        $Response.StatusCode | Should -Be 200
        $Response.Body.Metadata.id | Should -Be 'baseline-1'
        Should -Invoke New-CIPPBaseline -Times 0 -Exactly
        Should -Invoke Complete-CIPPManagedBaselineRequest -Times 1 -Exactly -ParameterFilter {
            $RequestId -eq 'request-9' -and $Version -eq '2' -and $User -eq 'admin@partner.example' -and $Baseline.templateName -eq 'Contoso baseline'
        }
    }

    It 'does not hand the request id or the version on as part of the baseline' {
        $null = Invoke-AddBaseline -Request (New-Request)

        Should -Invoke Complete-CIPPManagedBaselineRequest -Times 1 -Exactly -ParameterFilter {
            $Baseline.PSObject.Properties.Name -notcontains 'managedRequestId' -and $Baseline.PSObject.Properties.Name -notcontains 'managedVersion'
        }
    }

    It 'saves plainly once the baseline exists, so a second save never creates it twice' {
        $Response = Invoke-AddBaseline -Request (New-Request -Guid 'baseline-1')

        $Response.Body.Metadata.id | Should -Be 'plain-save'
        Should -Invoke Complete-CIPPManagedBaselineRequest -Times 0 -Exactly
        Should -Invoke New-CIPPBaseline -Times 1 -Exactly
    }

    It 'reports why the save was refused and saves nothing else' {
        Mock Complete-CIPPManagedBaselineRequest { throw [System.ArgumentException]::new('CyberDrain updated this baseline while you were reviewing it.') }

        $Response = Invoke-AddBaseline -Request (New-Request)

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*while you were reviewing it*'
        Should -Invoke New-CIPPBaseline -Times 0 -Exactly
    }

    It 'refuses before anything else when the tenant is outside the caller''s access' {
        Mock Get-CIPPBaselineOutOfScopeAssignment { 'Contoso' }

        (Invoke-AddBaseline -Request (New-Request)).StatusCode | Should -Be 403
        Should -Invoke Complete-CIPPManagedBaselineRequest -Times 0 -Exactly
    }
}
