# Pester tests for Invoke-AddAppTemplate
# Covers the guard that keeps applications CIPP cannot rebuild at deploy time out of
# application templates: a config carrying an IntuneBody read straight off Graph (it has an id)
# describes an app whose installer content lives inside Intune. Office and Edge are the exception
# because their body builders replay the stored body after stripping the read-only properties.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    # ContentType is unused by this endpoint but must be here: the endpoint is loaded through
    # [ScriptBlock]::Create, which resolves HttpResponseContext against the runspace type table
    # shared by every test file loaded the same way. The first such definition wins for the whole
    # run, and this file sorts first, so a narrower shape would make the endpoints that do set
    # ContentType fail their cast and fall into the wrong branch.
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    # Only the helpers these tests actually reach are stubbed. Get-CIPPAzDataTableEntity is not,
    # because the endpoint only calls it on the GUID upsert path, which no test here exercises.
    function Get-CippTable { param($tablename) @{} }
    function Add-CIPPAzDataTableEntity { param([switch]$Force, $Entity) $script:LastEntity = $Entity }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $LogData) }
    function Get-CippException {
        param($Exception)
        [pscustomobject]@{ NormalizedError = "$Exception" }
    }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/Applications/Invoke-AddAppTemplate.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    # A row as the Applications list hands it to Save as Template: the Graph object, id and all.
    function New-GraphAppRow {
        param([string]$OdataType, [string]$DisplayName)
        [pscustomobject]@{
            '@odata.type'   = $OdataType
            id              = '11111111-2222-3333-4444-555555555555'
            displayName     = $DisplayName
            publishingState = 'published'
            createdDateTime = '2026-01-01T00:00:00Z'
        }
    }

    function New-TemplateRequest {
        param([object[]]$Apps, [string]$DisplayName = 'Template A')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddAppTemplate' }
            Headers = @{ Authorization = 'Bearer token' }
            Body    = [pscustomobject]@{
                displayName = $DisplayName
                description = ''
                apps        = $Apps
            }
        }
    }
}

Describe 'Invoke-AddAppTemplate' {
    BeforeEach {
        $script:LastEntity = $null
    }

    It 'rejects an app whose config holds a Graph body with an id' {
        $Row = New-GraphAppRow -OdataType '#microsoft.graph.win32LobApp' -DisplayName 'FortiClient'
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'chocolateyApp'
                appName = 'FortiClient'
                config  = (@{ ApplicationName = 'FortiClient'; IntuneBody = $Row; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Match "'FortiClient' is an existing Intune application with uploaded installer content"
        $Response.Body.Results | Should -Match 'rebuilt from a package or script at deployment'
        $script:LastEntity | Should -BeNullOrEmpty
    }

    It 'rejects the same body when the config is supplied as an object rather than a string' {
        $Row = New-GraphAppRow -OdataType '#microsoft.graph.win32LobApp' -DisplayName 'FortiClient'
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'win32ScriptApp'
                appName = 'FortiClient'
                config  = [pscustomobject]@{ ApplicationName = 'FortiClient'; IntuneBody = $Row; AssignTo = 'On' }
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Match 'uploaded installer content'
        $script:LastEntity | Should -BeNullOrEmpty
    }

    It 'rejects the whole template when only one of its apps carries a Graph body' {
        $Row = New-GraphAppRow -OdataType '#microsoft.graph.winGetApp' -DisplayName 'Notepad++'
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'chocolateyApp'
                appName = 'Firefox'
                config  = (@{ ApplicationName = 'Firefox'; packagename = 'firefox'; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
            [pscustomobject]@{
                appType = 'StoreApp'
                appName = 'Notepad++'
                config  = (@{ ApplicationName = 'Notepad++'; IntuneBody = $Row; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Match "'Notepad\+\+' is an existing Intune application"
        $script:LastEntity | Should -BeNullOrEmpty
    }

    It 'still accepts an Office template saved from an existing deployment' {
        $Row = New-GraphAppRow -OdataType '#microsoft.graph.officeSuiteApp' -DisplayName 'Microsoft 365 Apps'
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'officeApp'
                appName = 'Microsoft 365 Apps'
                config  = (@{ ApplicationName = 'Microsoft 365 Apps'; IntuneBody = $Row; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Match 'Successfully saved app template'
        $script:LastEntity.PartitionKey | Should -Be 'AppTemplate'
        $script:LastEntity.JSON | Should -Match '"officeApp"'
    }

    It 'still accepts an Edge template saved from an existing deployment' {
        $Row = New-GraphAppRow -OdataType '#microsoft.graph.windowsMicrosoftEdgeApp' -DisplayName 'Microsoft Edge'
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'edgeApp'
                appName = 'Microsoft Edge'
                config  = (@{ ApplicationName = 'Microsoft Edge'; IntuneBody = $Row; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:LastEntity.JSON | Should -Match '"edgeApp"'
    }

    It 'still accepts a wizard built template with no stored Graph body' {
        $Request = New-TemplateRequest -Apps @(
            [pscustomobject]@{
                appType = 'chocolateyApp'
                appName = 'Firefox'
                config  = (@{ applicationName = 'Firefox'; packagename = 'firefox'; AssignTo = 'On' } | ConvertTo-Json -Depth 15 -Compress)
            }
        )

        $Response = Invoke-AddAppTemplate -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:LastEntity.JSON | Should -Match '"firefox"'
    }
}
