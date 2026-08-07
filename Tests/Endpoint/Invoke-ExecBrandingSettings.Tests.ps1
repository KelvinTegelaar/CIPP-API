# Pester tests for Invoke-ExecBrandingSettings.
#
# Covers the report-chrome fields (accent colour, footer, watermark) and the preset actions.
#
# Two properties matter beyond "does it save": a rejected field must not half-apply the rest of the
# request, and a boolean must be stored as a real boolean — Get-CIPPBrandingSettings distinguishes
# a stored $false from an absent property to decide whether a report keeps its footer.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBrandingSettings.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecBrandingSettings.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:LastFilter = $Filter; return $script:Rows }
    function Add-CIPPAzDataTableEntity {
        param($Entity, [switch]$Force)
        $script:SavedEntities += , $Entity
        $script:SavedEntity = $Entity
    }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:RemovedEntity = $Entity }
    function Write-LogMessage { param($API, $tenant, $headers, $message, $Sev) }
    function Get-CIPPBrandingSettings { param([switch]$PersistMigration) [pscustomobject]@{ colour = '#F77F00' } }
    function Get-CIPPBrandingPreset { param($Id, [switch]$SkipImageData) return $script:Presets }
    function Get-CIPPImage { param($PartitionKey, [string[]]$Id) if ($script:KnownImages -contains @($Id)[0]) { @{ id = @($Id)[0]; data = 'x' } } else { $null } }
    function Add-CIPPImage { param($PartitionKey, $Data) @{ id = 'new-image' } }
    function Remove-CIPPImage { param($PartitionKey, $Id) }
    function ConvertTo-CIPPCoverImageIdList {
        param($Value)
        if ($null -eq $Value -or $Value -eq '') { return , [string[]]@() }
        if ($Value -is [string]) {
            try {
                $Parsed = ConvertFrom-Json -InputObject $Value -ErrorAction Stop
                return , [string[]]@($Parsed | Where-Object { $_ })
            } catch { return , [string[]]@($Value) }
        }
        return , [string[]]@($Value | Where-Object { $_ })
    }

    . $FunctionPath

    function New-Request {
        param([hashtable]$Body)
        return [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecBrandingSettings' }
            Headers = @{ Authorization = 'token' }
            Query   = @{}
            Body    = [pscustomobject]$Body
        }
    }

    function Get-Saved {
        param([string]$PartitionKey = 'BrandingSettings')
        return $script:SavedEntities | Where-Object { $_.PartitionKey -eq $PartitionKey } | Select-Object -Last 1
    }
}

Describe 'Invoke-ExecBrandingSettings' {
    BeforeEach {
        $script:Rows = @([pscustomobject]@{
                PartitionKey = 'BrandingSettings'
                RowKey       = 'BrandingSettings'
                colour       = '#F77F00'
            })
        $script:SavedEntities = @()
        $script:SavedEntity = $null
        $script:RemovedEntity = $null
        $script:Presets = @()
        $script:KnownImages = @('logo-1', 'cover-1')
        $script:LastFilter = $null
    }

    Context 'Set — accent colour' {
        It 'stores a valid accent colour' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; secondaryColour = '#006666' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            (Get-Saved).secondaryColour | Should -Be '#006666'
        }

        It 'accepts an empty accent colour as "clear it"' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; secondaryColour = '' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            (Get-Saved).secondaryColour | Should -Be ''
        }

        It 'rejects a colour that is not hex' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; secondaryColour = 'rebeccapurple' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*Invalid secondary color*'
        }

        It 'saves nothing at all when one field in the request is invalid' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action          = 'Set'
                    colour          = '#342858'
                    secondaryColour = 'not-a-colour'
                })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Get-Saved | Should -BeNullOrEmpty
        }
    }

    Context 'Set — footer and watermark' {
        It 'stores footer text with its placeholders intact' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; footerText = '[tenantName] — [date]' }) | Out-Null
            (Get-Saved).footerText | Should -Be '[tenantName] — [date]'
        }

        It 'rejects footer text over 200 characters' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; footerText = ('x' * 201) })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*200 characters*'
        }

        It 'accepts footer text of exactly 200 characters' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; footerText = ('x' * 200) })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }

        It 'rejects watermark text over 40 characters' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; watermarkText = ('x' * 41) })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*40 characters*'
        }

        It 'stores an explicit false as a real boolean, not as absent' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; showFooter = $false }) | Out-Null

            $Saved = Get-Saved
            $Saved.showFooter | Should -BeOfType [bool]
            $Saved.showFooter | Should -BeFalse
        }

        It 'stores watermarkEnabled true' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; watermarkEnabled = $true }) | Out-Null
            (Get-Saved).watermarkEnabled | Should -BeTrue
        }

        It 'leaves untouched fields alone rather than resetting them' {
            # The UI sends the whole form, but an API caller may send one field.
            $script:Rows = @([pscustomobject]@{
                    PartitionKey = 'BrandingSettings'
                    RowKey       = 'BrandingSettings'
                    colour       = '#342858'
                    footerText   = 'Keep me'
                })

            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; watermarkText = 'DRAFT' }) | Out-Null

            $Saved = Get-Saved
            $Saved.footerText | Should -Be 'Keep me'
            $Saved.colour | Should -Be '#342858'
        }
    }

    Context 'Set — per-report default presets' {
        It 'stores the map as JSON, which is all a table property can hold' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action         = 'Set'
                    reportDefaults = [pscustomobject]@{ executive = 'preset-1'; sharing = 'preset-2' }
                }) | Out-Null

            $Saved = (Get-Saved).reportDefaults
            $Saved | Should -BeOfType [string]
            $Parsed = ConvertFrom-Json -InputObject $Saved
            $Parsed.executive | Should -Be 'preset-1'
            $Parsed.sharing | Should -Be 'preset-2'
        }

        It 'accepts a map already serialised by the caller' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action         = 'Set'
                    reportDefaults = '{"executive":"preset-1"}'
                }) | Out-Null

            (ConvertFrom-Json -InputObject (Get-Saved).reportDefaults).executive | Should -Be 'preset-1'
        }

        It 'clears every assignment when given an empty map' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; reportDefaults = '' }) | Out-Null
            (Get-Saved).reportDefaults | Should -Be '{}'
        }

        It 'rejects a value that is not valid JSON rather than storing something unreadable' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action         = 'Set'
                    reportDefaults = '{not json'
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*reportDefaults*'
        }

        It 'leaves the rest of the branding untouched' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action         = 'Set'
                    reportDefaults = [pscustomobject]@{ executive = 'preset-1' }
                }) | Out-Null

            (Get-Saved).colour | Should -Be '#F77F00'
        }
    }

    Context 'Set — per-role report colours' {
        # Headings, body, footer, charts and cards can each be coloured separately. Stored as one
        # JSON map rather than a column per role so a role added to the frontend needs no change
        # here, which is the same reasoning as reportDefaults above.
        It 'stores the map as JSON' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = '#112233'; bodyColour = '#445566' }
                }) | Out-Null

            $Parsed = ConvertFrom-Json -InputObject (Get-Saved).roleColours
            $Parsed.headingColour | Should -Be '#112233'
            $Parsed.bodyColour | Should -Be '#445566'
        }

        It 'accepts a map already serialised by the caller' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = '{"watermarkColour":"#ABCDEF"}'
                }) | Out-Null

            (ConvertFrom-Json -InputObject (Get-Saved).roleColours).watermarkColour | Should -Be '#ABCDEF'
        }

        It 'treats an empty value for a role as "follow the brand colour"' {
            # Not the same as an invalid colour: clearing a picker has to be allowed, and the theme
            # falls back to the brand colour for anything unset.
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = '' }
                }) | Out-Null

            (ConvertFrom-Json -InputObject (Get-Saved).roleColours).headingColour | Should -Be ''
        }

        It 'clears every role when given an empty map' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Set'; roleColours = '' }) | Out-Null
            (Get-Saved).roleColours | Should -Be '{}'
        }

        It 'rejects a colour that is not hex, naming the role that is wrong' {
            # An invalid colour reaches react-pdf as black without complaint, so it is caught here
            # rather than shipped to every report the role touches.
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = 'rebeccapurple' }
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*headingColour*'
        }

        It 'saves nothing at all when one role in the request is invalid' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = '#112233' }
                }) | Out-Null

            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = '#445566'; bodyColour = 'nope' }
                }) | Out-Null

            (ConvertFrom-Json -InputObject (Get-Saved).roleColours).headingColour | Should -Be '#112233'
        }

        It 'rejects a value that is not valid JSON' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = '{not json'
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*roleColours*'
        }

        It 'leaves the rest of the branding untouched' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'Set'
                    roleColours = [pscustomobject]@{ headingColour = '#112233' }
                }) | Out-Null

            (Get-Saved).colour | Should -Be '#F77F00'
        }
    }

    Context 'Reset' {
        It 'restores the report chrome defaults' {
            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'Reset' }) | Out-Null

            $Saved = Get-Saved
            $Saved.secondaryColour | Should -Be ''
            $Saved.footerText | Should -Be ''
            $Saved.showFooter | Should -BeTrue
            $Saved.showPageNumbers | Should -BeTrue
            $Saved.watermarkEnabled | Should -BeFalse
        }
    }

    Context 'SavePreset' {
        It 'saves a named preset and returns its id' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action = 'SavePreset'
                    name   = 'Client Facing'
                    colour = '#342858'
                })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results.id | Should -Not -BeNullOrEmpty

            $Saved = Get-Saved -PartitionKey 'BrandingPresets'
            $Saved.name | Should -Be 'Client Facing'
            $Saved.colour | Should -Be '#342858'
        }

        It 'updates in place when given an existing id' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action = 'SavePreset'
                    id     = 'preset-1'
                    name   = 'Renamed'
                    colour = '#006666'
                }) | Out-Null

            (Get-Saved -PartitionKey 'BrandingPresets').RowKey | Should -Be 'preset-1'
        }

        It 'requires a name' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'SavePreset'; colour = '#342858' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*name is required*'
        }

        It 'rejects a whitespace-only name' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'SavePreset'; name = '   ' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        }

        It 'rejects a cover stock we do not ship' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action     = 'SavePreset'
                    name       = 'Bad cover'
                    coverStock = 'https://evil.example/x.jpg'
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*Invalid cover stock*'
        }

        It 'rejects an image id that does not exist' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action      = 'SavePreset'
                    name        = 'Ghost logo'
                    logoImageId = 'does-not-exist'
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*logoImageId was not found*'
        }

        It 'accepts an image id from the shared gallery' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action       = 'SavePreset'
                    name         = 'With artwork'
                    logoImageId  = 'logo-1'
                    coverImageId = 'cover-1'
                    coverStock   = 'none'
                })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        }

        It 'stores booleans as booleans so the reader can tell them from absent' {
            Invoke-ExecBrandingSettings -Request (New-Request @{
                    Action     = 'SavePreset'
                    name       = 'No footer'
                    showFooter = $false
                }) | Out-Null

            $Saved = Get-Saved -PartitionKey 'BrandingPresets'
            $Saved.showFooter | Should -BeOfType [bool]
            $Saved.showFooter | Should -BeFalse
        }

        It 'rejects a name over 128 characters' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'SavePreset'; name = ('x' * 129) })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*128 characters*'
        }
    }

    Context 'DeletePreset' {
        It 'removes the preset row' {
            $script:Rows = @([pscustomobject]@{ PartitionKey = 'BrandingPresets'; RowKey = 'preset-1' })

            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'DeletePreset'; id = 'preset-1' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $script:RemovedEntity.RowKey | Should -Be 'preset-1'
        }

        It 'requires an id' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'DeletePreset' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*id is required*'
        }

        It 'reports a missing preset rather than silently succeeding' {
            $script:Rows = @()
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'DeletePreset'; id = 'gone' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*not found*'
        }

        It 'leaves the shared image gallery alone — another preset may still use those images' {
            $script:Rows = @([pscustomobject]@{ PartitionKey = 'BrandingPresets'; RowKey = 'preset-1'; logoImageId = 'logo-1' })
            Mock Remove-CIPPImage {}

            Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'DeletePreset'; id = 'preset-1' }) | Out-Null

            Should -Invoke Remove-CIPPImage -Times 0
        }
    }

    Context 'Unknown action' {
        It 'rejects an action it does not implement' {
            $Response = Invoke-ExecBrandingSettings -Request (New-Request @{ Action = 'DropTable' })
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $Response.Body.Results | Should -BeLike '*Invalid action*'
        }
    }
}
