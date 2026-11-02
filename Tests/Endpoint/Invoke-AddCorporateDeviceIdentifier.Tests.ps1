BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddCorporateDeviceIdentifier.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddCorporateDeviceIdentifier.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    function New-CorporateIdentifierRequest {
        param($Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddCorporateDeviceIdentifier' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-AddCorporateDeviceIdentifier' {
    BeforeEach {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            $Sent = $body | ConvertFrom-Json
            [pscustomobject]@{
                value = @($Sent.importedDeviceIdentities | ForEach-Object {
                        [pscustomobject]@{
                            importedDeviceIdentifier   = $_.importedDeviceIdentifier
                            importedDeviceIdentityType = $_.importedDeviceIdentityType
                            status                     = $true
                        }
                    })
            }
        }
        Mock -CommandName Write-LogMessage
    }

    It 'imports each device as a manufacturerModelSerial identity' {
        $req = New-CorporateIdentifierRequest @{
            tenantFilter   = @{ value = 'tenant.com'; label = 'Tenant' }
            devicePrepData = @(
                @{ manufacturer = 'Dell'; model = 'XPS 13'; serialNumber = 'SN001' },
                @{ manufacturer = 'HP'; model = 'EliteBook'; serialNumber = 'SN002' }
            )
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($res.Body.Results).Count | Should -Be 2
        @($res.Body.Results)[0].state | Should -Be 'success'
        @($res.Body.Results)[0].resultText | Should -BeLike 'Dell,XPS 13,SN001*imported successfully*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $uri -like '*importedDeviceIdentities/importDeviceIdentityList' -and
            $tenantid -eq 'tenant.com' -and
            $body -like '*manufacturerModelSerial*' -and
            $body -like '*"overwriteImportedDeviceIdentities":false*'
        }
    }

    It 'passes the overwrite flag through' {
        $req = New-CorporateIdentifierRequest @{
            tenantFilter      = @{ value = 'tenant.com' }
            overwriteExisting = $true
            devicePrepData    = @(@{ manufacturer = 'Dell'; model = 'XPS 13'; serialNumber = 'SN001' })
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $body -like '*"overwriteImportedDeviceIdentities":true*'
        }
    }

    It 'trims values before building the identifier' {
        $req = New-CorporateIdentifierRequest @{
            tenantFilter   = 'tenant.com'
            devicePrepData = @(@{ manufacturer = ' Dell '; model = ' XPS 13 '; serialNumber = ' SN001 ' })
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
            $body -like '*"importedDeviceIdentifier":"Dell,XPS 13,SN001"*'
        }
    }

    It 'reports devices the import rejected as errors' {
        Mock -CommandName New-GraphPOSTRequest -MockWith {
            [pscustomobject]@{
                value = @(
                    [pscustomobject]@{ importedDeviceIdentifier = 'Dell,XPS 13,SN001'; status = $true },
                    [pscustomobject]@{ importedDeviceIdentifier = 'HP,EliteBook,SN002'; status = $false }
                )
            }
        }
        $req = New-CorporateIdentifierRequest @{
            tenantFilter   = @{ value = 'tenant.com' }
            devicePrepData = @(
                @{ manufacturer = 'Dell'; model = 'XPS 13'; serialNumber = 'SN001' },
                @{ manufacturer = 'HP'; model = 'EliteBook'; serialNumber = 'SN002' }
            )
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($res.Body.Results)[0].state | Should -Be 'success'
        @($res.Body.Results)[1].state | Should -Be 'error'
        @($res.Body.Results)[1].resultText | Should -BeLike '*may already exist*'
    }

    It 'returns an error when a device is missing a field' {
        $req = New-CorporateIdentifierRequest @{
            tenantFilter   = @{ value = 'tenant.com' }
            devicePrepData = @(@{ manufacturer = 'Dell'; model = ''; serialNumber = 'SN001' })
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        @($res.Body.Results)[0].state | Should -Be 'error'
        @($res.Body.Results)[0].resultText | Should -BeLike '*manufacturer, model and serial number*'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'returns an error when no devices are provided' {
        $req = New-CorporateIdentifierRequest @{
            tenantFilter = @{ value = 'tenant.com' }
        }
        $res = Invoke-AddCorporateDeviceIdentifier -Request $req -TriggerMetadata $null

        $res.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        @($res.Body.Results)[0].resultText | Should -BeLike '*No devices*'
        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}
