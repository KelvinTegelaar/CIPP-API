# Pester tests for Invoke-AddUserDefaults.
#
# The endpoint behind Add/Edit Template on the User Templates page. It copies the posted form into a
# hand-written template object and stores that as JSON, so any field missing from that object is
# silently dropped: the save still returns OK, the template just comes back without it. That is how
# the custom user attributes (officeLocation, employeeId, ...) went missing (CyberDrain/CIPP#671).

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddUserDefaults.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddUserDefaults.ps1 under Modules/' }

    # Azure Functions binding types do not exist outside the Functions host - fake them.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    # Get-CippTable returns a splattable hashtable, so the entity stub needs the matching parameters.
    function Add-CIPPAzDataTableEntity { param($Context, $TableName, $Force, $Entity) }
    function Get-CippException { param($Exception) }
    function Get-CippTable { param($tablename) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-TemplateRequest {
        param([hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            templateName = 'Sales'
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'AddUserDefaults' }
        }
    }
}

Describe 'Invoke-AddUserDefaults' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ Context = 'ctx'; TableName = 'templates' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
    }

    It 'stores the custom user attributes on the template' {
        $Request = New-TemplateRequest -Body @{
            defaultAttributes = [pscustomobject]@{
                officeLocation = [pscustomobject]@{ Value = 'Copenhagen' }
            }
        }

        $Response = Invoke-AddUserDefaults -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.PartitionKey -eq 'UserDefaultTemplate' -and
            ($Entity.JSON | ConvertFrom-Json).defaultAttributes.officeLocation.Value -eq 'Copenhagen'
        }
    }
}
