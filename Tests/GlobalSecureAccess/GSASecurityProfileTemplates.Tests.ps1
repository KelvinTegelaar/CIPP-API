BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value -replace "'", "''" }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPGSAProfileLink.ps1')
    foreach ($Name in 'Invoke-AddGSASecurityProfileTemplate', 'Invoke-ListGSASecurityProfileTemplates', 'Invoke-RemoveGSASecurityProfileTemplate') { . (Join-Path $Folder "$Name.ps1") }

    function Invoke-Add([hashtable]$Body) { Invoke-AddGSASecurityProfileTemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddGSASecurityProfileTemplate' }; Body = [pscustomobject]$Body; Query = @{} }) }
    function Get-Row([string]$Partition, [string]$Guid, [hashtable]$Json) { [pscustomobject]@{ PartitionKey = $Partition; RowKey = $Guid; JSON = ($Json | ConvertTo-Json -Depth 10) } }
    function Get-ValidBody {
        @{
            name = ' Staff '; priority = 1000; state = 'enabled'
            policies = @(
                @{ policy = @{ label = 'old label'; value = 'pol-1' }; priority = 100; state = 'enabled'; loggingState = 'disabled' }
                @{ policy = 'pol-2'; priority = 200 }
            )
        }
    }
}

Describe 'Invoke-AddGSASecurityProfileTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { (Get-Row 'GSAFilteringPolicyTemplate' 'pol-1' @{ name = 'Block risky' }), (Get-Row 'GSAFilteringPolicyTemplate' 'pol-2' @{ name = 'Allow partners' }) } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Get-CIPPAzDataTableEntity { Get-Row 'GSASecurityProfileTemplate' 'prof-1' @{ name = 'Guests'; priority = 2000 } } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'rejects bad input with every problem listed, before touching the table' {
        $Response = Invoke-Add @{ name = ''; priority = 65000; state = 'on'; policies = @(@{ policy = 'p'; priority = 50 }, @{ policy = 'p'; priority = 300; state = 'maybe' }) }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Be "Invalid security profile template: name is required; priority must be a number from 100 to 64999; state must be enabled or disabled, not 'on'; link priority for p must be a number from 100 to 65000; filtering policy p is linked twice; link state and logging for p must be enabled or disabled"
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'requires at least one link and unique link priorities' {
        (Invoke-Add @{ name = 'x'; priority = 1000; state = 'enabled' }).Body.Results | Should -Be 'Invalid security profile template: link at least one filtering policy'
        $Body = Get-ValidBody
        $Body.policies[1].priority = 100
        (Invoke-Add $Body).Body.Results | Should -BeLike '*link priority 100 is used twice'
    }

    It 'stores the links in the autocomplete shape with current policy names and defaulted states' {
        $Response = Invoke-Add (Get-ValidBody)
        $Response.Body.Results | Should -Be "Created security profile template 'Staff'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Stored = $Entity.JSON | ConvertFrom-Json
            $Entity.PartitionKey -eq 'GSASecurityProfileTemplate' -and $Stored.name -eq 'Staff' -and $Stored.priority -eq 1000 -and
            $Stored.policies[0].policy.label -eq 'Block risky' -and $Stored.policies[0].policy.value -eq 'pol-1' -and $Stored.policies[0].loggingState -eq 'disabled' -and
            $Stored.policies[1].policy.label -eq 'Allow partners' -and $Stored.policies[1].state -eq 'enabled' -and $Stored.policies[1].loggingState -eq 'enabled'
        }
    }

    It 'refuses a link to a filtering policy template that does not exist' {
        $Body = Get-ValidBody
        $Body.policies[1].policy = @{ label = 'Gone'; value = 'pol-9' }
        $Response = Invoke-Add $Body
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike "*these filtering policy templates do not exist: 'Gone'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }

    It 'refuses a name or priority another template uses, but not its own on update' {
        $Body = Get-ValidBody
        $Body.name = 'GUESTS'
        (Invoke-Add $Body).Body.Results | Should -BeLike "*A security profile template named 'GUESTS' already exists"
        $Body = Get-ValidBody
        $Body.priority = 2000
        (Invoke-Add $Body).Body.Results | Should -BeLike "*Priority 2000 is already used by security profile template 'Guests'"
        $Body.GUID = 'prof-1'
        $Body.name = 'Guests'
        (Invoke-Add $Body).Body.Results | Should -Be "Updated security profile template 'Guests'"
    }

    It 'returns 404 for an unknown GUID' {
        $Body = Get-ValidBody
        $Body.GUID = 'missing'
        (Invoke-Add $Body).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}

Describe 'Invoke-ListGSASecurityProfileTemplates' {
    It 'returns templates with their GUID, or 404 for an unknown GUID' {
        Mock Get-CIPPAzDataTableEntity { Get-Row 'GSASecurityProfileTemplate' 'prof-1' @{ name = 'Staff' } }
        @((Invoke-ListGSASecurityProfileTemplates -Request ([pscustomobject]@{ Query = @{} })).Body.GUID) | Should -Be @('prof-1')
        Mock Get-CIPPAzDataTableEntity {}
        (Invoke-ListGSASecurityProfileTemplates -Request ([pscustomobject]@{ Query = @{ GUID = 'nope' } })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}

Describe 'Invoke-RemoveGSASecurityProfileTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { Get-Row 'GSASecurityProfileTemplate' 'prof-1' @{ name = 'Staff' } } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Remove-CIPPAzDataTableEntity {}
    }

    It 'removes a template no CA template links, ignoring a CA template that only mentions the GUID elsewhere' {
        Mock Get-CIPPAzDataTableEntity { Get-Row 'CATemplate' 'ca-1' @{ displayName = 'Other'; description = 'see prof-1' } } -ParameterFilter { $Filter -like "*'CATemplate'*" }
        (Invoke-RemoveGSASecurityProfileTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'prof-1' } })).Body.Results | Should -Be "Removed security profile template 'Staff'"
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1
    }

    It 'refuses while a CA template links it, naming that template' {
        Mock Get-CIPPAzDataTableEntity { Get-Row 'CATemplate' 'ca-1' @{ displayName = 'Staff web filtering'; sessionControls = @{ globalSecureAccessFilteringProfile = @{ profileId = @{ label = 'Staff'; value = 'prof-1' }; isEnabled = $true } } } } -ParameterFilter { $Filter -like "*'CATemplate'*" }
        $Response = Invoke-RemoveGSASecurityProfileTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'prof-1' } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike "*'Staff' is still linked by Conditional Access templates: Staff web filtering"
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'requires an ID and returns 404 for an unknown template' {
        (Invoke-RemoveGSASecurityProfileTemplate -Request ([pscustomobject]@{ Query = @{}; Body = $null })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        (Invoke-RemoveGSASecurityProfileTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'nope' } })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}
