# A GitHub block in the save request is a push instruction, not part of the template: it must
# never land in the stored JSON, the save must complete first, and a push happens exactly once
# against the saved GUID. A push failure must not fail the save.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Standards/Invoke-AddStandardsTemplate.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-CippTable { param($tablename) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Push-CIPPTemplateToRepo { param($GUID, $FullName, $Message, $Branch) }

    . $FunctionPath

    function New-Request {
        param($Guid, $GitHub)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"tester@example.com"}'))
        $BodyProps = [ordered]@{
            GUID         = $Guid
            templateName = 'Repo template'
            tenantFilter = @([pscustomobject]@{ value = 'AllTenants'; type = 'Tenant' })
            standards    = [pscustomobject]@{ AuditLog = [pscustomobject]@{ remediate = $true } }
        }
        if ($GitHub) { $BodyProps['GitHub'] = $GitHub }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddStandardsTemplate' }
            Headers = @{ 'x-ms-client-principal' = $Principal; 'x-ms-original-url' = 'https://cipp.example.com/api/AddStandardsTemplate' }
            Body    = [pscustomobject]$BodyProps
        }
    }
}

Describe 'Invoke-AddStandardsTemplate GitHub push' {
    BeforeEach {
        $script:Written = $null
        Mock -CommandName Test-CIPPAccess -MockWith { @('AllTenants') }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub' } }
        Mock -CommandName Add-AzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { $script:Written = $Entity }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'saves first, then pushes exactly once with the saved GUID and given FullName/Message, and strips GitHub from stored JSON' {
        Mock -CommandName Push-CIPPTemplateToRepo -MockWith { @{ resultText = "Template 'Repo template' uploaded"; state = 'success' } }

        $Response = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-1' -GitHub ([pscustomobject]@{ FullName = 'Org/repo'; Message = 'commit msg' }))

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        Should -Invoke Push-CIPPTemplateToRepo -Times 1 -ParameterFilter { $GUID -eq 'guid-1' -and $FullName -eq 'Org/repo' -and $Message -eq 'commit msg' }

        ($script:Written.JSON | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'GitHub'
        $Response.Body.Results | Should -BeLike '*Pushed to Org/repo*'
    }

    It 'does not push when no GitHub block is present' {
        Mock -CommandName Push-CIPPTemplateToRepo -MockWith { @{ resultText = 'unused'; state = 'success' } }
        $Response = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-2')

        Should -Invoke Push-CIPPTemplateToRepo -Times 0
        $Response.Body.Results | Should -Be 'Successfully added template'
    }

    It 'reports a push failure in Results without failing the save' {
        Mock -CommandName Push-CIPPTemplateToRepo -MockWith { throw 'GitHub API is down' }

        $Response = Invoke-AddStandardsTemplate -Request (New-Request -Guid 'guid-3' -GitHub ([pscustomobject]@{ FullName = 'Org/repo'; Message = 'commit msg' }))

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike '*Failed to push*'
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Error' }
    }
}
