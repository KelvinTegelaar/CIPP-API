BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/GlobalSecureAccess'

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Test-CippTemplateWriteAccess { param($Permission, $PartitionKey, $RowKey) $true }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value -replace "'", "''" }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-NormalizedError { param($Message) $Message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPGSAFilteringRule.ps1')
    foreach ($Name in 'Invoke-AddGSAFilteringPolicyTemplate', 'Invoke-ListGSAFilteringPolicyTemplates', 'Invoke-RemoveGSAFilteringPolicyTemplate') { . (Join-Path $Folder "$Name.ps1") }

    function Invoke-Add([hashtable]$Body) { Invoke-AddGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddGSAFilteringPolicyTemplate' }; Body = [pscustomobject]$Body; Query = @{} }) }
    function Get-PolicyRow([string]$Guid, [string]$Name) { [pscustomobject]@{ PartitionKey = 'GSAFilteringPolicyTemplate'; RowKey = $Guid; JSON = (@{ name = $Name; action = 'block'; policyRules = @() } | ConvertTo-Json) } }
    $script:ValidBody = @{
        name        = ' Block risky '
        action      = 'block'
        policyRules = @(
            @{ name = 'Categories'; ruleType = 'webCategory'; destinations = @('Weapons', 'Gambling', 'Gambling') }
            @{ name = 'Sites'; ruleType = 'fqdn'; destinations = @(@{ '@odata.type' = '#microsoft.graph.networkaccess.fqdn'; value = '*.example.org' }) }
            @{ name = 'Paths'; ruleType = 'url'; destinations = @('www.example.org/blocked/*') }
        )
    }
}

Describe 'Invoke-AddGSAFilteringPolicyTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { @(Get-PolicyRow 'g-1' 'Existing') }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'rejects bad input with every problem listed, before touching the table' {
        $Response = Invoke-Add @{ name = ''; action = 'deny'; policyRules = @(@{ name = 'a'; ruleType = 'ipRange'; destinations = @('10.0.0.0/8') }, @{ name = 'A'; ruleType = 'fqdn'; destinations = @(' ') }) }
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Be "Invalid filtering policy template: name is required; action must be block or allow, not 'deny'; rule 'a' has an unknown type 'ipRange'; use webCategory, fqdn or url; rule name 'A' is used twice; rule 'A' has no destinations"
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0
    }

    It 'requires at least one rule, whether the list is empty or missing, alongside other errors' {
        (Invoke-Add @{ name = 'Empty'; action = 'allow'; policyRules = @() }).Body.Results | Should -Be 'Invalid filtering policy template: at least one rule is required'
        (Invoke-Add @{ name = 'Empty'; action = 'deny' }).Body.Results | Should -Be "Invalid filtering policy template: action must be block or allow, not 'deny'; at least one rule is required"
    }

    It 'stores the policy in Graph shape with typed rules and sorted, de-duplicated destinations' {
        $Response = Invoke-Add $script:ValidBody
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be "Created filtering policy template 'Block risky'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Stored = $Entity.JSON | ConvertFrom-Json
            $Entity.PartitionKey -eq 'GSAFilteringPolicyTemplate' -and $Entity.RowKey -eq $Entity.GUID -and $Entity.RowKey -match '^[0-9a-f-]{36}$' -and
            $Stored.name -eq 'Block risky' -and
            $Stored.policyRules[0].'@odata.type' -eq '#microsoft.graph.networkaccess.webCategoryFilteringRule' -and
            ($Stored.policyRules[0].destinations.name -join ',') -eq 'Gambling,Weapons' -and
            $Stored.policyRules[0].destinations[0].'@odata.type' -eq '#microsoft.graph.networkaccess.webCategory' -and
            $Stored.policyRules[1].destinations[0].value -eq '*.example.org' -and
            $Stored.policyRules[2].'@odata.type' -eq '#microsoft.graph.networkaccess.urlDestinationFilteringRule' -and
            $Stored.policyRules[2].destinations[0].'@odata.type' -eq '#microsoft.graph.networkaccess.url'
        }
    }

    It 'saves a tenant policy as listed by ListGSAFilteringPolicies, dropping the tenant ids' {
        $Rule = [pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategoryFilteringRule'; id = 'r-1'; name = 'cats'; ruleType = 'webCategory'; destinations = @([pscustomobject]@{ '@odata.type' = '#microsoft.graph.networkaccess.webCategory'; name = 'Gambling'; displayName = 'Gambling'; group = 'Liability' }) }
        (Invoke-Add @{ name = 'Block risky'; description = $null; action = 'block'; policyRules = @($Rule) }).Body.Results | Should -Be "Created filtering policy template 'Block risky'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Stored = $Entity.JSON | ConvertFrom-Json
            -not $Stored.policyRules[0].id -and ($Stored.policyRules[0].destinations[0].PSObject.Properties.Name -join ',') -eq '@odata.type,name'
        }
    }

    It 'updates the template named by GUID' {
        $Body = $script:ValidBody.Clone()
        $Body.GUID = 'g-1'
        $Body.name = 'Existing'
        (Invoke-Add $Body).Body.Results | Should -Be "Updated filtering policy template 'Existing'"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'g-1' }
    }

    It 'returns 404 for an unknown GUID and 400 for a name another template uses' {
        $Body = $script:ValidBody.Clone()
        $Body.GUID = 'g-missing'
        (Invoke-Add $Body).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)

        $Body = $script:ValidBody.Clone()
        $Body.name = 'EXISTING'
        $Response = Invoke-Add $Body
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike "*A filtering policy template named 'EXISTING' already exists"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}

Describe 'Invoke-ListGSAFilteringPolicyTemplates' {
    It 'returns every template with its GUID, or 404 for an unknown GUID' {
        Mock Get-CIPPAzDataTableEntity { @((Get-PolicyRow 'g-1' 'One'), (Get-PolicyRow 'g-2' 'Two')) }
        $Response = Invoke-ListGSAFilteringPolicyTemplates -Request ([pscustomobject]@{ Query = @{} })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.GUID) | Should -Be @('g-1', 'g-2')

        Mock Get-CIPPAzDataTableEntity {}
        $Response = Invoke-ListGSAFilteringPolicyTemplates -Request ([pscustomobject]@{ Query = @{ GUID = "x' or 1 eq 1" } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 'GSAFilteringPolicyTemplate' and RowKey eq 'x'' or 1 eq 1'" }
    }
}

Describe 'Invoke-RemoveGSAFilteringPolicyTemplate' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { Get-PolicyRow 'g-1' 'Block risky' } -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        Mock Remove-CIPPAzDataTableEntity {}
    }

    It 'requires an ID' {
        (Invoke-RemoveGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Query = @{}; Body = $null })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'removes an unlinked template' {
        $Response = Invoke-RemoveGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'g-1' } })
        $Response.Body.Results | Should -Be "Removed filtering policy template 'Block risky'"
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'g-1' }
    }

    It 'refuses while a security profile template links it, naming that template' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ JSON = (@{ name = 'Staff'; policies = @(@{ policy = @{ label = 'Block risky'; value = 'g-1' } }) } | ConvertTo-Json -Depth 5) }
            [pscustomobject]@{ JSON = (@{ name = 'Guests'; policies = @(@{ policy = @{ label = 'Other'; value = 'g-9' } }) } | ConvertTo-Json -Depth 5) }
        } -ParameterFilter { $Filter -like "*'GSASecurityProfileTemplate'*" }
        $Response = Invoke-RemoveGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'g-1' } })
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike "*'Block risky' is still linked by security profile templates: Staff"
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0
    }

    It 'returns 404 for an unknown template' {
        Mock Get-CIPPAzDataTableEntity {} -ParameterFilter { $Filter -like "*'GSAFilteringPolicyTemplate'*" }
        (Invoke-RemoveGSAFilteringPolicyTemplate -Request ([pscustomobject]@{ Query = @{ ID = 'nope' } })).StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }
}
